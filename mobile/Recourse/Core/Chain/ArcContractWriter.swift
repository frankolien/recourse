import Foundation
@preconcurrency import BigInt
@preconcurrency import Web3Core

enum ContractWriteError: Error, Equatable, Sendable {
    case invalidABI(String)
    case unsupportedMethod(String)
    case invalidHashData
    case receiptTimedOut
    case malformedPaidEvent
}

actor ArcContractWriter: ContractWriting {
    private static let paidEventTopic = ChainHash(
        trusted: "0x49235e5c4cbb20ad7f9091e87b06dd12cddf489d77e8fd97a83cc5d4fc323e47"
    )

    private let configuration: AppConfiguration
    private let signer: any BuyerSigner
    private let transport: any ArcTransactionTransport
    private let pollClock: any TransactionPollClock
    private let maximumReceiptPolls: Int
    private let erc20: EthereumContract
    private let escrow: EthereumContract

    init(
        configuration: AppConfiguration,
        signer: any BuyerSigner,
        transport: any ArcTransactionTransport,
        pollClock: any TransactionPollClock = OneSecondTransactionPollClock(),
        maximumReceiptPolls: Int = 90,
        bundle: Bundle = .main
    ) throws {
        self.configuration = configuration
        self.signer = signer
        self.transport = transport
        self.pollClock = pollClock
        self.maximumReceiptPolls = maximumReceiptPolls
        erc20 = try Self.makeContract(
            abi: ContractABI.erc20.load(from: bundle),
            address: configuration.usdcAddress,
            name: ContractABI.erc20.rawValue
        )
        escrow = try Self.makeContract(
            abi: ContractABI.recourseEscrow.load(from: bundle),
            address: configuration.escrowAddress,
            name: ContractABI.recourseEscrow.rawValue
        )
    }

    func approveUSDC(amount: USDCAmount) async throws -> ChainHash {
        let data = try encode(
            contract: erc20,
            method: "approve",
            parameters: [try web3Address(configuration.escrowAddress), BigUInt(amount.baseUnits)]
        )
        return try await submit(to: configuration.usdcAddress, data: data)
    }

    func pay(_ request: PaymentRequest) async throws -> ChainHash {
        let data = try encode(
            contract: escrow,
            method: "pay",
            parameters: [
                BigUInt(request.policyID),
                BigUInt(request.amount.baseUnits),
                try data(from: request.orderReference)
            ]
        )
        return try await submit(to: configuration.escrowAddress, data: data)
    }

    func fileDispute(
        paymentID: UInt64,
        claimType: ClaimType,
        evidence: [UploadedEvidence]
    ) async throws -> ChainHash {
        let encodedEvidence: [[Any]] = try evidence.map { item in
            [BigUInt(item.kind.rawValue), try data(from: item.hash)]
        }
        let callData = try encode(
            contract: escrow,
            method: "fileDispute",
            parameters: [BigUInt(paymentID), BigUInt(claimType.rawValue), encodedEvidence]
        )
        return try await submit(to: configuration.escrowAddress, data: callData)
    }

    func resolve(paymentID: UInt64) async throws -> ChainHash {
        let data = try encode(
            contract: escrow,
            method: "resolve",
            parameters: [BigUInt(paymentID)]
        )
        return try await submit(to: configuration.escrowAddress, data: data)
    }

    func waitForReceipt(transactionHash: ChainHash) async throws -> ChainReceipt {
        for poll in 0 ..< maximumReceiptPolls {
            if let receipt = try await transport.receipt(transactionHash: transactionHash) {
                return ChainReceipt(
                    transactionHash: receipt.transactionHash,
                    outcome: receipt.outcome,
                    paymentID: try paymentID(from: receipt.logs)
                )
            }
            if poll + 1 < maximumReceiptPolls {
                try await pollClock.sleep()
            }
        }
        throw ContractWriteError.receiptTimedOut
    }

    private func submit(to address: EthereumAddress, data: Data) async throws -> ChainHash {
        let signerAddress = try await signer.address()
        let transaction = try await transport.prepareTransaction(
            from: signerAddress,
            to: address,
            data: data,
            chainID: configuration.chainID
        )
        let rawTransaction = try await signer.sign(transaction)
        return try await transport.send(rawTransaction: rawTransaction)
    }

    private func encode(
        contract: EthereumContract,
        method: String,
        parameters: [Any]
    ) throws -> Data {
        guard let data = contract.method(method, parameters: parameters, extraData: nil) else {
            throw ContractWriteError.unsupportedMethod(method)
        }
        return data
    }

    private func paymentID(from logs: [TransactionLogRecord]) throws -> UInt64? {
        guard let paidLog = logs.first(where: {
            $0.address.value.lowercased() == configuration.escrowAddress.value.lowercased()
                && $0.topics.first == Self.paidEventTopic
        }) else {
            return nil
        }
        guard paidLog.topics.count >= 2 else {
            throw ContractWriteError.malformedPaidEvent
        }
        let encodedID = paidLog.topics[1].value.dropFirst(2)
        guard encodedID.prefix(48).allSatisfy({ $0 == "0" }),
              let paymentID = UInt64(encodedID.suffix(16), radix: 16) else {
            throw ContractWriteError.malformedPaidEvent
        }
        return paymentID
    }

    private static func makeContract(
        abi: String,
        address: EthereumAddress,
        name: String
    ) throws -> EthereumContract {
        guard let contractAddress = Web3Core.EthereumAddress(address.value) else {
            throw ContractWriteError.invalidABI(name)
        }
        do {
            return try EthereumContract(abi, at: contractAddress)
        } catch {
            throw ContractWriteError.invalidABI(name)
        }
    }

    private func web3Address(_ address: EthereumAddress) throws -> Web3Core.EthereumAddress {
        guard let result = Web3Core.EthereumAddress(address.value) else {
            throw ContractWriteError.invalidHashData
        }
        return result
    }

    private func data(from hash: ChainHash) throws -> Data {
        let value = hash.value.dropFirst(2)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index ..< next], radix: 16) else {
                throw ContractWriteError.invalidHashData
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}
