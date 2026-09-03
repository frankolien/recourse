import Foundation
@preconcurrency import BigInt

/// How a contract call reaches the chain.
///
/// Before the Safe, the on-device key signed a transaction and paid its gas. Now the
/// Safe executes a user operation through the bundler and pays from its own balance.
/// The contract writer builds the same calldata either way and hands it here.
protocol ArcSubmitter: Sendable {
    /// The account the calls come from: the Safe, or the plain key before there is one.
    func sender() async throws -> EthereumAddress
    /// Send a call and return the hash of the transaction that carried it.
    func submit(to address: EthereumAddress, data: Data) async throws -> ChainHash
}

/// The original path: sign with the key, send the raw transaction.
struct KeySubmitter: ArcSubmitter {
    let signer: any BuyerSigner
    let transport: any ArcTransactionTransport
    let chainID: UInt64

    func sender() async throws -> EthereumAddress {
        try await signer.address()
    }

    func submit(to address: EthereumAddress, data: Data) async throws -> ChainHash {
        let from = try await signer.address()
        let transaction = try await transport.prepareTransaction(from: from, to: address, data: data, chainID: chainID)
        let raw = try await signer.sign(transaction)
        return try await transport.send(rawTransaction: raw)
    }
}

enum SafeSubmitError: Error, Equatable {
    case operationFailed(ChainHash)
    case operationTimedOut
}

/// The Safe path: wrap the call in `executeUserOp`, price and estimate it with the
/// bundler, sign the operation with both keys, send it, and wait for the transaction
/// that included it.
actor SafeSubmitter: ArcSubmitter {
    private static let getNonceSelector = Data([0x35, 0x56, 0x7e, 0x1a])

    private let signer: SafeAccountSigner
    private let bundler: any BundlerTransport
    private let rpc: any ArcRPCTransport
    private let chainID: UInt64
    private let pollClock: any TransactionPollClock
    private let maximumPolls: Int

    init(
        signer: SafeAccountSigner,
        bundler: any BundlerTransport,
        rpc: any ArcRPCTransport,
        chainID: UInt64,
        pollClock: any TransactionPollClock = OneSecondTransactionPollClock(),
        maximumPolls: Int = 60
    ) {
        self.signer = signer
        self.bundler = bundler
        self.rpc = rpc
        self.chainID = chainID
        self.pollClock = pollClock
        self.maximumPolls = maximumPolls
    }

    func sender() async throws -> EthereumAddress {
        await signer.safe
    }

    func submit(to address: EthereumAddress, data: Data) async throws -> ChainHash {
        let account = await signer.account
        let safe = await signer.safe
        let entryPoint = EthereumAddress(trusted: account.entryPoint)
        let module = EthereumAddress(trusted: account.module)

        let callData = SafeCalldata.executeUserOp(to: address, data: data)
        let nonce = try await entryPointNonce(safe: safe, entryPoint: entryPoint)
        let price = try await bundler.gasPrice()

        var operation = UserOperation(
            sender: safe,
            nonce: nonce,
            callData: callData,
            callGasLimit: 0,
            verificationGasLimit: 0,
            preVerificationGas: 0,
            maxFeePerGas: price.maxFeePerGas,
            maxPriorityFeePerGas: price.maxPriorityFeePerGas,
            signature: Self.frame(try await signer.placeholderSignature())
        )
        let gas = try await bundler.estimate(operation, entryPoint: entryPoint)
        operation.callGasLimit = gas.callGasLimit
        operation.verificationGasLimit = gas.verificationGasLimit
        operation.preVerificationGas = gas.preVerificationGas

        let hash = SafeHashing.operationHash(
            module: module,
            chainID: chainID,
            safe: safe,
            nonce: nonce,
            callData: callData,
            verificationGasLimit: gas.verificationGasLimit,
            callGasLimit: gas.callGasLimit,
            preVerificationGas: gas.preVerificationGas,
            maxPriorityFeePerGas: price.maxPriorityFeePerGas,
            maxFeePerGas: price.maxFeePerGas,
            entryPoint: entryPoint
        )
        operation.signature = Self.frame(try await signer.signSafeHash(hash))

        let operationHash = try await bundler.send(operation, entryPoint: entryPoint)
        for poll in 0 ..< maximumPolls {
            if let receipt = try await bundler.receipt(operationHash: operationHash) {
                guard receipt.success else { throw SafeSubmitError.operationFailed(receipt.transactionHash) }
                return receipt.transactionHash
            }
            if poll + 1 < maximumPolls {
                try await pollClock.sleep()
            }
        }
        throw SafeSubmitError.operationTimedOut
    }

    /// The module reads six bytes of validAfter and six of validUntil ahead of the
    /// owner signatures. Both zero: valid whenever the bundler includes it.
    private static func frame(_ safeSignature: Data) -> Data {
        Data(repeating: 0, count: 12) + safeSignature
    }

    /// `getNonce(address,uint192)` on the EntryPoint, key 0.
    private func entryPointNonce(safe: EthereumAddress, entryPoint: EthereumAddress) async throws -> BigUInt {
        let call = Self.getNonceSelector + ABIWord.address(safe) + ABIWord.uint(0)
        let answer = try await rpc.call(to: entryPoint, data: call)
        guard answer.count == 32 else { throw BundlerError.malformed("nonce") }
        return BigUInt(answer)
    }
}
