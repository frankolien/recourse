import Foundation

protocol BuyerSigner: Sendable {
    func address() async throws -> EthereumAddress
    func sign(_ transaction: UnsignedTransaction) async throws -> Data
    func signEIP712(_ typedData: Data) async throws -> Data
    func reset() async throws

    // Declared here, not only in the extension below, so a call through `any
    // BuyerSigner` reaches the signer's own answer. An extension-only method is
    // dispatched statically, and every caller was getting the default: "yes, there
    // is a wallet", which made a restore impossible to reach.
    func exportPrivateKey() async throws -> Data
    func importPrivateKey(_ privateKey: Data) async throws
    func signHash(_ digest: Data) async throws -> Data
    func hasWallet() async -> Bool
    func setMintsOnDemand(_ allowed: Bool) async
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

    /// Sign a 32-byte digest as-is: 65 bytes, recovery id 27 or 28.
    ///
    /// The Safe asks its owners for exactly this, over hashes it has already framed
    /// in its own domain, so no prefix and no second hash belong here. Only the
    /// on-device key can do it; it is not gated by the payment authorizer because the
    /// Device Key prompts for Face ID on the same signature, and one prompt is enough.
    func signHash(_ digest: Data) async throws -> Data {
        throw BuyerSignerError.invalidAccount
    }

    /// Whether this device already holds a wallet, asked without creating one.
    ///
    /// `address()` mints a keystore when none exists, which is right for every other
    /// caller and exactly wrong here: asking "is there a wallet to restore onto"
    /// must not answer by making one. Signers that always have a key say so.
    func hasWallet() async -> Bool { true }

    /// Whether `address()` may mint a key when none exists. Off while the account
    /// store is still finding out if this account's wallet lives elsewhere: a key
    /// minted in that window is a stray that the server then refuses, and the
    /// reinstall that lost the keychain turns into an afternoon.
    func setMintsOnDemand(_ allowed: Bool) async {}
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
    /// No key here, and none may be made yet: the account's wallet is on another
    /// phone, or the store has not yet found out. Recovery is the way in.
    case walletElsewhere
}
