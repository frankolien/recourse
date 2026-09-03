import CryptoKit
// Scrypt comes from CryptoSwift, AES-GCM from CryptoKit. Both frameworks export
// a type called AES, so every use below names the framework it came from.
import CryptoSwift
import Foundation

/// Encrypts the wallet key so an account can carry it to another device.
///
/// The defect this exists for: the signing key is minted on the device and stored in
/// its keychain, so signing in with the same account on a second phone produces a new,
/// empty wallet, and losing the phone loses the money. Neither is acceptable in
/// something people keep money in.
///
/// The server stores only what comes out of `seal`. It never sees the PIN and never
/// sees the key, so holding the ciphertext is not custody: the backend cannot move
/// anyone's funds, and a full database leak still leaves an attacker with scrypt to
/// get through.
///
/// **The honest limitation.** A six digit PIN is 10^6 guesses. Scrypt at these
/// parameters is what stands between an attacker who has stolen the ciphertext and the
/// key, and it makes each guess cost memory and time rather than a hash. That is a real
/// wall, not an unbreakable one, which is why `minimumPINLength` is a floor rather than
/// a recommendation and why a longer passphrase is accepted. Passkey PRF removes the
/// secret entirely and is the endgame; this ships now and is replaceable without a
/// migration, because the stored blob is versioned.
enum WalletBackup {
    /// Interactive scrypt parameters. N is the memory and time cost, and 2^15 with r=8
    /// is roughly 32 MB per guess: slow enough to matter against a short PIN, fast
    /// enough that unlocking on a phone is not a visible wait.
    static let scryptN = 32_768
    static let scryptR = 8
    static let scryptP = 1
    static let keyLength = 32

    /// Six digits is the floor because it is what people will actually use. Anything
    /// shorter is not worth the false comfort.
    static let minimumPINLength = 6

    /// The format on the wire and at rest. Versioned because the KDF will be replaced
    /// by a passkey derived secret, and an old blob must still open afterwards.
    struct Envelope: Codable, Equatable, Sendable {
        var version: Int = 1
        var kdf: String = "scrypt"
        var n: Int
        var r: Int
        var p: Int
        /// Base64. Fresh per seal, so the same PIN never produces the same ciphertext.
        var salt: String
        var nonce: String
        var ciphertext: String
        /// The address this key controls, so a restore can name the wallet before
        /// asking for a PIN and can prove afterwards that it decrypted the right one.
        var address: String
    }

    enum Failure: Error, Equatable {
        case pinTooShort
        case wrongPIN
        case unsupportedVersion(Int)
        case malformed(String)

        var message: String {
            switch self {
            case .pinTooShort:
                return "Use at least \(WalletBackup.minimumPINLength) digits."
            case .wrongPIN:
                return "That PIN did not unlock the backup."
            case .unsupportedVersion(let version):
                return "This backup was made by a newer version of Recourse (format \(version))."
            case .malformed(let detail):
                return "The backup could not be read: \(detail)."
            }
        }
    }

    /// Encrypt a private key under a PIN.
    ///
    /// The cost parameters are arguments only so the test suite can exercise the format
    /// without paying 32 MB of scrypt twenty times over. Nothing in the app passes them:
    /// weakening the cost is the one change here that silently removes the protection.
    static func seal(
        privateKey: Data,
        pin: String,
        address: String,
        n: Int = scryptN,
        r: Int = scryptR,
        p: Int = scryptP
    ) throws -> Envelope {
        guard pin.count >= minimumPINLength else { throw Failure.pinTooShort }

        var salt = Data(count: 16)
        // A fresh salt per seal is what stops one precomputation from opening every
        // backup this app has ever made.
        let generated = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard generated == errSecSuccess else { throw Failure.malformed("no randomness available") }

        let derived = try derive(pin: pin, salt: salt, n: n, r: r, p: p)
        let sealed = try CryptoKit.AES.GCM.seal(privateKey, using: SymmetricKey(data: derived))
        guard let combinedNonce = sealed.nonce.withUnsafeBytes({ Data($0) }) as Data? else {
            throw Failure.malformed("nonce unavailable")
        }

        return Envelope(
            n: n,
            r: r,
            p: p,
            salt: salt.base64EncodedString(),
            nonce: combinedNonce.base64EncodedString(),
            ciphertext: (sealed.ciphertext + sealed.tag).base64EncodedString(),
            address: address.lowercased()
        )
    }

    /// Decrypt a private key with a PIN.
    ///
    /// A wrong PIN is indistinguishable from a corrupted blob at the cipher level, and
    /// both surface as `wrongPIN`, because the only actionable thing a person can do
    /// about either is try again.
    static func open(_ envelope: Envelope, pin: String) throws -> Data {
        guard envelope.version == 1 else { throw Failure.unsupportedVersion(envelope.version) }
        guard envelope.kdf == "scrypt" else { throw Failure.malformed("unknown key derivation") }
        guard
            let salt = Data(base64Encoded: envelope.salt),
            let nonce = Data(base64Encoded: envelope.nonce),
            let body = Data(base64Encoded: envelope.ciphertext),
            body.count > 16
        else {
            throw Failure.malformed("missing or invalid fields")
        }

        // The parameters come from the envelope rather than the constants above, so a
        // backup written before a cost increase still opens.
        let derived = try derive(pin: pin, salt: salt, n: envelope.n, r: envelope.r, p: envelope.p)
        let box: CryptoKit.AES.GCM.SealedBox
        do {
            box = try CryptoKit.AES.GCM.SealedBox(
                nonce: CryptoKit.AES.GCM.Nonce(data: nonce),
                ciphertext: body.prefix(body.count - 16),
                tag: body.suffix(16)
            )
        } catch {
            throw Failure.malformed("ciphertext is not well formed")
        }

        do {
            return try CryptoKit.AES.GCM.open(box, using: SymmetricKey(data: derived))
        } catch {
            throw Failure.wrongPIN
        }
    }

    private static func derive(
        pin: String,
        salt: Data,
        n: Int = scryptN,
        r: Int = scryptR,
        p: Int = scryptP
    ) throws -> Data {
        do {
            let bytes = try Scrypt(
                password: Array(pin.utf8),
                salt: Array(salt),
                dkLen: keyLength,
                N: n,
                r: r,
                p: p
            ).calculate()
            return Data(bytes)
        } catch {
            throw Failure.malformed("key derivation failed")
        }
    }
}
