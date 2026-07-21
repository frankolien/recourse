import Foundation

struct UnsignedTransaction: Hashable, Sendable {
    let chainID: UInt64
    let from: EthereumAddress
    let to: EthereumAddress
    let nonce: UInt64
    let gasLimit: UInt64
    let gasPrice: UInt64
    let data: Data
}

struct TransactionLogRecord: Hashable, Sendable {
    let address: EthereumAddress
    let topics: [ChainHash]
}

struct TransactionReceiptRecord: Hashable, Sendable {
    let transactionHash: ChainHash
    let outcome: ChainReceipt.Outcome
    let logs: [TransactionLogRecord]
}

protocol ArcTransactionTransport: Sendable {
    func prepareTransaction(
        from: EthereumAddress,
        to: EthereumAddress,
        data: Data,
        chainID: UInt64
    ) async throws -> UnsignedTransaction
    func send(rawTransaction: Data) async throws -> ChainHash
    func receipt(transactionHash: ChainHash) async throws -> TransactionReceiptRecord?
}

protocol TransactionPollClock: Sendable {
    func sleep() async throws
}

struct OneSecondTransactionPollClock: TransactionPollClock {
    func sleep() async throws {
        try await Task.sleep(for: .seconds(1))
    }
}
