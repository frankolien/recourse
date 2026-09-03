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

    /// Nor can anything else accept one.
    func importPrivateKey(_ privateKey: Data) async throws {
        throw BuyerSignerError.invalidAccount
    }

    /// Whether this device already holds a wallet, asked without creating one.
    ///
    /// `address()` mints a keystore when none exists, which is right for every other
    /// caller and exactly wrong here: asking "is there a wallet to restore onto"
    /// must not answer by making one. Signers that always have a key say so.
    func hasWallet() async -> Bool { true }
}

enum BuyerSignerError: Error, Equatable, Sendable {
    case entropyUnavailable
    case keystoreCreationFailed
    case keystoreSerializationFailed
    case corruptKeystore
    case missingPassword
    case invalidAccount
    case signingFailed
    /// Importing onto a device that already has a wallet. Refused rather than
    /// overwritten: the existing key may hold funds nobody else has a copy of.
    case walletAlreadyExists
}
