import Foundation

protocol BuyerSigner: Sendable {
    func address() async throws -> EthereumAddress
    func sign(_ transaction: UnsignedTransaction) async throws -> Data
    func signEIP712(_ typedData: Data) async throws -> Data
    func reset() async throws
}

extension BuyerSigner {
    /// Only the on-device signer can surrender a key. Anything else conforming to
    /// this protocol (a remote signer, a test double) has nothing to export.
    func exportPrivateKey() async throws -> Data {
        throw BuyerSignerError.invalidAccount
    }
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
