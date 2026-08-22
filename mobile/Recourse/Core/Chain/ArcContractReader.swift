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
    private let vault: EthereumContract
    private let fxRouter: EthereumContract?
    private let fxPair: EthereumContract?

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
        vault = try Self.makeContract(
            abi: ContractABI.settlementVault.load(from: bundle),
            address: configuration.settlementVaultAddress,
            name: ContractABI.settlementVault.rawValue
        )
        // Optional: a chain with no FX venue deployed simply has no Convert.
        if configuration.fxRouterAddress != nil, configuration.eurcAddress != nil {
            fxRouter = try Self.makeContract(
                abi: ContractABI.fxRouter.load(from: bundle),
                address: configuration.fxRouterAddress!,
                name: ContractABI.fxRouter.rawValue
            )
            // Bound to the router's address only so the contract can be built here;
            // the pair address is not known until getPair is asked at call time, and
            // every call below supplies it explicitly.
            fxPair = try Self.makeContract(
                abi: ContractABI.fxPair.load(from: bundle),
                address: configuration.fxRouterAddress!,
                name: ContractABI.fxPair.rawValue
            )
        } else {
            fxRouter = nil
            fxPair = nil
        }
    }

    static func live(configuration: AppConfiguration = .live) throws -> ArcContractReader {
        try ArcContractReader(
            configuration: configuration,
            transport: HTTPArcRPCTransport(rpcURL: configuration.rpcURL)
        )
    }

    func fxAmountOut(amountIn: USDCAmount) async throws -> BigUInt {
        guard let fxRouter,
              let router = configuration.fxRouterAddress,
              let eurc = configuration.eurcAddress else {
            throw ContractReadError.unsupportedMethod("getAmountsOut")
        }

        let path = [
            try web3Address(configuration.usdcAddress),
            try web3Address(eurc),
        ]
        let result = try await call(
            contract: fxRouter,
            address: router,
            method: "getAmountsOut",
            parameters: [BigUInt(amountIn.baseUnits), path]
        )
        // getAmountsOut returns one amount per hop; the last is what arrives.
        guard let amounts = result["0"] as? [BigUInt], let out = amounts.last else {
            throw ContractReadError.malformedResult(method: "getAmountsOut")
        }
        return out
    }

    /// The pool's reserves, USDC first.
    ///
    /// Quoting goes through the router so the number shown matches the number
    /// filled, but a ceiling is a question about the pool's depth rather than about
    /// one trade, and asking the router would mean a round trip per candidate size.
    /// Two reads answer it once and the curve does the rest locally.
    func fxReserves() async throws -> FXReserves {
        guard let fxPair, let fxRouter,
              let router = configuration.fxRouterAddress,
              let eurc = configuration.eurcAddress else {
            throw ContractReadError.unsupportedMethod("getReserves")
        }

        let usdc = try web3Address(configuration.usdcAddress)
        let eurcAddress = try web3Address(eurc)
        let pairResult = try await call(
            contract: fxRouter,
            address: router,
            method: "getPair",
            parameters: [usdc, eurcAddress]
        )
        let pair = try domainAddress(pairResult["0"], method: "getPair")
        guard pair.value.lowercased() != Self.zeroAddress else {
            throw ContractReadError.malformedResult(method: "getPair")
        }

        let reserves = try await call(
            contract: fxPair,
            address: pair,
            method: "getReserves",
            parameters: []
        )
        guard let reserve0 = reserves["0"] as? BigUInt, let reserve1 = reserves["1"] as? BigUInt else {
            throw ContractReadError.malformedResult(method: "getReserves")
        }

        // The pair stores reserves in the token order the router sorted them into, so
        // which one is USDC is a fact about the two addresses, not about the pool.
        let usdcIsToken0 = configuration.usdcAddress.value.lowercased() < eurc.value.lowercased()
        return usdcIsToken0
            ? FXReserves(usdc: reserve0, eurc: reserve1)
            : FXReserves(usdc: reserve1, eurc: reserve0)
    }

    private static let zeroAddress = "0x0000000000000000000000000000000000000000"

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

    func vaultState(of owner: EthereumAddress) async throws -> VaultState {
        let vaultAddress = configuration.settlementVaultAddress
        let assets = try await call(contract: vault, address: vaultAddress, method: "totalAssets")
        let shares = try await call(contract: vault, address: vaultAddress, method: "totalShares")
        let outstanding = try await call(contract: vault, address: vaultAddress, method: "outstanding")
        let mine = try await call(
            contract: vault,
            address: vaultAddress,
            method: "sharesOf",
            parameters: [try web3Address(owner)]
        )
        return VaultState(
            totalAssets: USDCAmount(baseUnits: try uint64(assets["0"], method: "totalAssets")),
            totalShares: try uint64(shares["0"], method: "totalShares"),
            outstanding: USDCAmount(baseUnits: try uint64(outstanding["0"], method: "outstanding")),
            myShares: try uint64(mine["0"], method: "sharesOf")
        )
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
