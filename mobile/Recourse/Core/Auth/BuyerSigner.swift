import Foundation

protocol BuyerSigner: Sendable {
    func address() async throws -> EthereumAddress
    func sign(_ transaction: UnsignedTransaction) async throws -> Data
    func reset() async throws
}

enum BuyerSignerError: Error, Equatable, Sendable {
    case entropyUnavailable
    case keystoreCreationFailed
    case keystoreSerializationFailed
    case corruptKeystore
    case missingPassword
    case invalidAccount
    case signingFailed
}
