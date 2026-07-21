import Foundation
@preconcurrency import BigInt
@preconcurrency import Web3Core

enum ContractReadError: Error, Equatable, Sendable {
    case missingABI(String)
    case invalidABI(String)
    case unsupportedMethod(String)
    case invalidRPCResponse
    case rpc(code: Int, message: String)
    case malformedResult(method: String)
    case integerOverflow(method: String)
    case unknownPaymentStatus(UInt8)
    case unknownClaimType(UInt8)
}

actor ArcContractReader: ContractReading {
    private let configuration: AppConfiguration
    private let transport: any ArcRPCTransport
    private let erc20: EthereumContract
    private let policyRegistry: EthereumContract
    private let escrow: EthereumContract

    init(
        configuration: AppConfiguration,
        transport: any ArcRPCTransport,
        bundle: Bundle = .main
    ) throws {
        self.configuration = configuration
        self.transport = transport
        erc20 = try Self.makeContract(
            abi: ContractABI.erc20.load(from: bundle),
            address: configuration.usdcAddress,
            name: ContractABI.erc20.rawValue
        )
        policyRegistry = try Self.makeContract(
            abi: ContractABI.policyRegistry.load(from: bundle),
            address: configuration.policyRegistryAddress,
            name: ContractABI.policyRegistry.rawValue
        )
        escrow = try Self.makeContract(
            abi: ContractABI.recourseEscrow.load(from: bundle),
            address: configuration.escrowAddress,
            name: ContractABI.recourseEscrow.rawValue
        )
    }

    static func live(configuration: AppConfiguration = .live) throws -> ArcContractReader {
        try ArcContractReader(
            configuration: configuration,
            transport: HTTPArcRPCTransport(rpcURL: configuration.rpcURL)
        )
    }

    func usdcBalance(of owner: EthereumAddress) async throws -> USDCAmount {
        let result = try await call(
            contract: erc20,
            address: configuration.usdcAddress,
            method: "balanceOf",
            parameters: [try web3Address(owner)]
        )
        return USDCAmount(baseUnits: try uint64(result["0"], method: "balanceOf"))
    }

    func allowance(owner: EthereumAddress, spender: EthereumAddress) async throws -> USDCAmount {
        let result = try await call(
            contract: erc20,
            address: configuration.usdcAddress,
            method: "allowance",
            parameters: [try web3Address(owner), try web3Address(spender)]
        )
        return USDCAmount(baseUnits: try uint64(result["0"], method: "allowance"))
    }

    func policy(id: UInt64) async throws -> PolicyRecord {
        let policyResult = try await call(
            contract: policyRegistry,
            address: configuration.policyRegistryAddress,
            method: "getPolicy",
            parameters: [BigUInt(id)]
        )
        let hashResult = try await call(
            contract: policyRegistry,
            address: configuration.policyRegistryAddress,
            method: "policyHash",
            parameters: [BigUInt(id)]
        )

        guard let tuple = policyResult["0"] as? [Any], tuple.count == 4 else {
            throw ContractReadError.malformedResult(method: "getPolicy")
        }
        return PolicyRecord(
            id: id,
            merchant: try domainAddress(tuple[0], method: "getPolicy"),
            disputeWindow: try uint64(tuple[1], method: "getPolicy"),
            policyHash: try chainHash(hashResult["0"], method: "policyHash")
        )
    }

    func payment(id: UInt64) async throws -> PaymentRecord {
        let result = try await call(
            contract: escrow,
            address: configuration.escrowAddress,
            method: "getPayment",
            parameters: [BigUInt(id)]
        )
        guard let tuple = result["0"] as? [Any], tuple.count == 15 else {
            throw ContractReadError.malformedResult(method: "getPayment")
        }

        let filedAt = try uint64(tuple[7], method: "getPayment")
        let rawClaimType = try uint8(tuple[8], method: "getPayment")
        let rawStatus = try uint8(tuple[14], method: "getPayment")
        guard let status = PaymentStatus(rawValue: rawStatus) else {
            throw ContractReadError.unknownPaymentStatus(rawStatus)
        }

        let claimType: ClaimType?
        if filedAt == 0 {
            claimType = nil
        } else {
            guard let decodedClaimType = ClaimType(rawValue: rawClaimType) else {
                throw ContractReadError.unknownClaimType(rawClaimType)
            }
            claimType = decodedClaimType
        }

        return PaymentRecord(
            id: id,
            buyer: try domainAddress(tuple[0], method: "getPayment"),
            merchant: try domainAddress(tuple[1], method: "getPayment"),
            beneficiary: try domainAddress(tuple[2], method: "getPayment"),
            policyID: try uint64(tuple[3], method: "getPayment"),
            amount: USDCAmount(baseUnits: try uint64(tuple[4], method: "getPayment")),
            paidAt: try uint64(tuple[6], method: "getPayment"),
            filedAt: filedAt,
            claimType: claimType,
            evidenceMask: try uint16(tuple[9], method: "getPayment"),
            attestationType: try uint8(tuple[10], method: "getPayment"),
            attestationValue: try uint8(tuple[11], method: "getPayment"),
            verdictBPS: try uint16(tuple[13], method: "getPayment"),
            status: status
        )
    }

    func previewVerdict(paymentID: UInt64) async throws -> VerdictPreview {
        let result = try await call(
            contract: escrow,
            address: configuration.escrowAddress,
            method: "previewVerdict",
            parameters: [BigUInt(paymentID)]
        )
        guard let tuple = result["0"] as? [Any], tuple.count == 4,
              let requiresReturn = tuple[1] as? Bool,
              let matched = tuple[3] as? Bool else {
            throw ContractReadError.malformedResult(method: "previewVerdict")
        }

        return VerdictPreview(
            refundBPS: try uint16(tuple[0], method: "previewVerdict"),
            requiresReturn: requiresReturn,
            ruleIndex: try uint8(tuple[2], method: "previewVerdict"),
            matched: matched,
            verdictHash: try chainHash(result["1"], method: "previewVerdict")
        )
    }

    func resolveDelay() async throws -> UInt64 {
        let result = try await call(
            contract: escrow,
            address: configuration.escrowAddress,
            method: "resolveDelay"
        )
        return try uint64(result["0"], method: "resolveDelay")
    }

    private func call(
        contract: EthereumContract,
        address: EthereumAddress,
        method: String,
        parameters: [Any] = []
    ) async throws -> [String: Any] {
        guard let callData = contract.method(method, parameters: parameters, extraData: nil) else {
            throw ContractReadError.unsupportedMethod(method)
        }
        let response = try await transport.call(to: address, data: callData)
        do {
            return try contract.decodeReturnData(method, data: response)
        } catch {
            throw ContractReadError.malformedResult(method: method)
        }
    }

    private static func makeContract(
        abi: String,
        address: EthereumAddress,
        name: String
    ) throws -> EthereumContract {
        guard let contractAddress = Web3Core.EthereumAddress(address.value) else {
            throw ContractReadError.invalidABI(name)
        }
        do {
            return try EthereumContract(abi, at: contractAddress)
        } catch {
            throw ContractReadError.invalidABI(name)
        }
    }

    private func web3Address(_ address: EthereumAddress) throws -> Web3Core.EthereumAddress {
        guard let result = Web3Core.EthereumAddress(address.value) else {
            throw ContractReadError.malformedResult(method: "address")
        }
        return result
    }

    private func domainAddress(_ value: Any?, method: String) throws -> EthereumAddress {
        guard let address = value as? Web3Core.EthereumAddress else {
            throw ContractReadError.malformedResult(method: method)
        }
        return try EthereumAddress(address.address)
    }

    private func chainHash(_ value: Any?, method: String) throws -> ChainHash {
        guard let data = value as? Data, data.count == 32 else {
            throw ContractReadError.malformedResult(method: method)
        }
        let value = "0x" + data.map { String(format: "%02x", $0) }.joined()
        return try ChainHash(value)
    }

    private func uint64(_ value: Any?, method: String) throws -> UInt64 {
        guard let value = value as? BigUInt else {
            throw ContractReadError.malformedResult(method: method)
        }
        guard value <= BigUInt(UInt64.max) else {
            throw ContractReadError.integerOverflow(method: method)
        }
        return UInt64(value)
    }

    private func uint16(_ value: Any?, method: String) throws -> UInt16 {
        let value = try uint64(value, method: method)
        guard value <= UInt16.max else {
            throw ContractReadError.integerOverflow(method: method)
        }
        return UInt16(value)
    }

    private func uint8(_ value: Any?, method: String) throws -> UInt8 {
        let value = try uint64(value, method: method)
        guard value <= UInt8.max else {
            throw ContractReadError.integerOverflow(method: method)
        }
        return UInt8(value)
    }
}
