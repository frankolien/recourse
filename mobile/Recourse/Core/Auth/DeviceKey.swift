import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// The Device Key: a P-256 key that never leaves this phone.
///
/// Made inside the Secure Enclave, so there is no key material to copy, back up or
/// sync; what exists is a handle the enclave will sign with, after the person
/// confirms with Face ID or the passcode. On-chain it is one of the account's Safe
/// owners, standing behind a small contract that checks its signatures.
///
/// `.userPresence` rather than `.biometryCurrentSet`: re-enrolling a face must not
/// destroy the key, and the passcode is an acceptable fallback. The prompt is a
/// courtesy; the security boundary is that spending needs this key and the Cloud Key
/// together.
protocol DeviceKeySigning: Sendable {
    /// The public key as two 32-byte coordinates, made on first use.
    func publicKey() async throws -> DevicePublicKey
    /// Sign a 32-byte digest. The enclave signs the digest as given, no second hash.
    func sign(digest: Data) async throws -> Data
    /// Whether a key exists on this phone for the active account, without making one.
    func hasKey() async -> Bool
    /// Forget the key. Used when a phone is being restored onto a different account.
    func reset() async throws
}

struct DevicePublicKey: Hashable, Sendable {
    let x: Data
    let y: Data

    var xHex: String { x.hexString }
    var yHex: String { y.hexString }
}

enum DeviceKeyError: Error, Equatable {
    case enclaveUnavailable(String)
    case notFound
    case signingFailed(String)
    case malformedSignature
    case digestNotThirtyTwoBytes
}

/// Where the key handle lives. The keychain on a phone; memory in tests, where the
/// host is unsigned and the keychain refuses every call.
protocol DeviceKeyStore: Sendable {
    func load(tag: Data) throws -> SecKey?
    func create(tag: Data) throws -> SecKey
    func delete(tag: Data) throws
}

actor SecureEnclaveDeviceKey: DeviceKeySigning {
    private static let service = "com.recourse.buyer.device-key"
    private let store: any DeviceKeyStore
    private let scope: @Sendable () -> String?

    init(
        store: any DeviceKeyStore = KeychainDeviceKeyStore(),
        scope: @escaping @Sendable () -> String? = { ActiveAccount.scope }
    ) {
        self.store = store
        self.scope = scope
    }

    /// One key per signed-in account, like the keystore, so two accounts on one phone
    /// never share a Device Key.
    private var tag: Data {
        let name = scope().map { "\(Self.service).\($0)" } ?? Self.service
        return Data(name.utf8)
    }

    func publicKey() async throws -> DevicePublicKey {
        let key = try store.load(tag: tag) ?? store.create(tag: tag)
        return try Self.coordinates(of: key)
    }

    func sign(digest: Data) async throws -> Data {
        guard digest.count == 32 else { throw DeviceKeyError.digestNotThirtyTwoBytes }
        guard let key = try store.load(tag: tag) else { throw DeviceKeyError.notFound }
        var error: Unmanaged<CFError>?
        guard let der = SecKeyCreateSignature(
            key,
            .ecdsaSignatureDigestX962SHA256,
            digest as CFData,
            &error
        ) as Data? else {
            let reason = (error?.takeRetainedValue() as Error?)?.localizedDescription ?? "unknown"
            throw DeviceKeyError.signingFailed(reason)
        }
        return try Self.rawSignature(fromDER: der)
    }

    func hasKey() async -> Bool {
        (try? store.load(tag: tag)) != nil
    }

    func reset() async throws {
        try store.delete(tag: tag)
    }

    // MARK: Encoding

    /// The public key comes out as X9.63 `04 || X || Y`.
    static func coordinates(of key: SecKey) throws -> DevicePublicKey {
        guard let publicKey = SecKeyCopyPublicKey(key) else {
            throw DeviceKeyError.enclaveUnavailable("no public key")
        }
        var error: Unmanaged<CFError>?
        guard let x963 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?,
              x963.count == 65, x963.first == 0x04 else {
            throw DeviceKeyError.enclaveUnavailable("public key is not an uncompressed point")
        }
        return DevicePublicKey(x: x963[1 ..< 33], y: x963[33 ..< 65])
    }

    /// DER `SEQUENCE { INTEGER r, INTEGER s }` to the 64 bytes the contract reads.
    static func rawSignature(fromDER der: Data) throws -> Data {
        guard let signature = try? P256.Signing.ECDSASignature(derRepresentation: der) else {
            throw DeviceKeyError.malformedSignature
        }
        let raw = signature.rawRepresentation
        guard raw.count == 64 else { throw DeviceKeyError.malformedSignature }
        return raw
    }
}

/// The real store: a permanent, enclave-backed key behind user presence.
struct KeychainDeviceKeyStore: DeviceKeyStore {
    func load(tag: Data) throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let item else {
            throw DeviceKeyError.enclaveUnavailable("lookup failed (\(status))")
        }
        // The query asked for a key reference; that is what comes back.
        return (item as! SecKey)
    }

    func create(tag: Data) throws -> SecKey {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .userPresence],
            &accessError
        ) else {
            throw DeviceKeyError.enclaveUnavailable("access control: \(String(describing: accessError))")
        }

        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessControl as String: access,
            ],
        ]
        // The simulator has no enclave and refuses the token; a plain keychain key
        // stands in there so the flow can be exercised. Never on a device.
        #if !targetEnvironment(simulator)
        attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        #endif

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let reason = (error?.takeRetainedValue() as Error?)?.localizedDescription ?? "unknown"
            throw DeviceKeyError.enclaveUnavailable(reason)
        }
        return key
    }

    func delete(tag: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DeviceKeyError.enclaveUnavailable("delete failed (\(status))")
        }
    }
}

/// Keys that live only as long as the process. For tests, and nothing else.
final class EphemeralDeviceKeyStore: DeviceKeyStore, @unchecked Sendable {
    private var keys: [Data: SecKey] = [:]
    private let lock = NSLock()

    func load(tag: Data) throws -> SecKey? {
        lock.withLock { keys[tag] }
    }

    func create(tag: Data) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw DeviceKeyError.enclaveUnavailable("ephemeral key: \(String(describing: error))")
        }
        lock.withLock { keys[tag] = key }
        return key
    }

    func delete(tag: Data) throws {
        lock.withLock { keys[tag] = nil }
    }
}
