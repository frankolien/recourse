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
    private let submitter: any ArcSubmitter
    private let pollClock: any TransactionPollClock
    private let maximumReceiptPolls: Int
    private let erc20: EthereumContract
    private let registry: EthereumContract
    private let escrow: EthereumContract
    private let vault: EthereumContract

    init(
        configuration: AppConfiguration,
        signer: any BuyerSigner,
        transport: any ArcTransactionTransport,
        submitter: (any ArcSubmitter)? = nil,
        pollClock: any TransactionPollClock = OneSecondTransactionPollClock(),
        maximumReceiptPolls: Int = 90,
        bundle: Bundle = .main
    ) throws {
        self.configuration = configuration
        self.signer = signer
        self.transport = transport
        // Without a Safe the key signs and pays as it always did.
        self.submitter = submitter ?? KeySubmitter(signer: signer, transport: transport, chainID: configuration.chainID)
        self.pollClock = pollClock
        self.maximumReceiptPolls = maximumReceiptPolls
        erc20 = try Self.makeContract(
            abi: ContractABI.erc20.load(from: bundle),
            address: configuration.usdcAddress,
            name: ContractABI.erc20.rawValue
        )
        registry = try Self.makeContract(
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
    }

    func approveUSDC(amount: USDCAmount) async throws -> ChainHash {
        let data = try encode(
            contract: erc20,
            method: "approve",
            parameters: [try web3Address(configuration.escrowAddress), BigUInt(amount.baseUnits)]
        )
        return try await submit(to: configuration.usdcAddress, data: data)
    }

    func transferUSDC(to recipient: EthereumAddress, amount: USDCAmount) async throws -> ChainHash {
        let data = try encode(
            contract: erc20,
            method: "transfer",
            parameters: [try web3Address(recipient), BigUInt(amount.baseUnits)]
        )
        return try await submit(to: configuration.usdcAddress, data: data)
    }

    /// Cash a cheque: submit the writer's authorization and move their USDC to the
    /// recipient.
    ///
    /// Anyone can submit this, which is what makes a cheque a cheque. The token checks
    /// the signature against `from`, so the person cashing it pays the gas but cannot
    /// change a single term: not the amount, not the recipient, not the expiry.
    ///
    /// The `bytes` overload takes a signature of any shape: 65 bytes from a plain key,
    /// or a Safe's packed owner signatures, which the token checks through EIP-1271.
    func cashCheque(_ cheque: Cheque, signature: Data) async throws -> ChainHash {
        let data = try encode(
            contract: erc20,
            method: "transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,bytes)",
            parameters: [
                try web3Address(cheque.from),
                try web3Address(cheque.to),
                BigUInt(cheque.amount.baseUnits),
                BigUInt(cheque.validAfter),
                BigUInt(cheque.validBefore),
                cheque.nonce,
                Self.normalized(signature),
            ]
        )
        return try await submit(to: configuration.usdcAddress, data: data)
    }

    /// Void an uncashed cheque by burning its nonce. Only the writer can sign this, and
    /// once it lands the authorization can never be used.
    func voidCheque(nonce: Data, cancellationSignature: Data) async throws -> ChainHash {
        let data = try encode(
            contract: erc20,
            method: "cancelAuthorization(address,bytes32,bytes)",
            parameters: [try web3Address(try await signer.address()), nonce, Self.normalized(cancellationSignature)]
        )
        return try await submit(to: configuration.usdcAddress, data: data)
    }

    /// A 65 byte key signature with its recovery id as the token wants it. Libraries
    /// disagree about emitting 0/1 or 27/28, so the low form is lifted. Anything that
    /// is not 65 bytes is a contract signature and passes through untouched.
    static func normalized(_ signature: Data) -> Data {
        guard signature.count == 65 else { return signature }
        var fixed = signature
        let last = fixed.index(before: fixed.endIndex)
        if fixed[last] < 27 { fixed[last] += 27 }
        return fixed
    }

    /// A 65 byte signature as the token wants it. The recovery id is stored as 0 or 1
    /// and the token expects 27 or 28, and libraries disagree about which they emit, so
    /// both are accepted and normalized rather than assumed.
    static func split(signature: Data) throws -> (BigUInt, Data, Data) {
        guard signature.count == 65 else { throw BuyerSignerError.signingFailed }
        let r = signature.prefix(32)
        let s = signature.dropFirst(32).prefix(32)
        let raw = signature[signature.index(signature.startIndex, offsetBy: 64)]
        let v = raw < 27 ? BigUInt(raw) + 27 : BigUInt(raw)
        return (v, Data(r), Data(s))
    }

    func registerStarterPolicy() async throws -> ChainHash {
        let day = 24 * 60 * 60
        let rules: [[Any]] = [
            [
                BigUInt(0),
                BigUInt(0),
                BigUInt(1),
                BigUInt(2),
                BigUInt(14 * day),
                BigUInt(10_000),
                false
            ],
            [
                BigUInt(1),
                BigUInt(1),
                BigUInt(0),
                BigUInt(0),
                BigUInt(3 * day),
                BigUInt(10_000),
                true
            ]
        ]
        let data = try encode(
            contract: registry,
            method: "registerPolicy",
            parameters: [
                BigUInt(14 * day),
                BigUInt(0),
                rules,
                "ipfs://recourse-mobile-starter-policy"
            ]
        )
        return try await submit(to: configuration.policyRegistryAddress, data: data)
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

    func approveVaultUSDC(amount: USDCAmount) async throws -> ChainHash {
        let data = try encode(
            contract: erc20,
            method: "approve",
            parameters: [try web3Address(configuration.settlementVaultAddress), BigUInt(amount.baseUnits)]
        )
        return try await submit(to: configuration.usdcAddress, data: data)
    }

    func vaultDeposit(amount: USDCAmount) async throws -> ChainHash {
        let data = try encode(
            contract: vault,
            method: "deposit",
            parameters: [BigUInt(amount.baseUnits)]
        )
        return try await submit(to: configuration.settlementVaultAddress, data: data)
    }

    func vaultWithdraw(shares: UInt64) async throws -> ChainHash {
        let data = try encode(
            contract: vault,
            method: "withdraw",
            parameters: [BigUInt(shares)]
        )
        return try await submit(to: configuration.settlementVaultAddress, data: data)
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
        try await submitter.submit(to: address, data: data)
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
