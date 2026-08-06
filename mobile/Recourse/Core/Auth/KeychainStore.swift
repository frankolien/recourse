import Foundation
import Security

actor KeychainStore {
    private let service: String
    private let synchronizable: Bool

    /// - Parameter synchronizable: whether items travel through iCloud Keychain
    ///   to the user's other devices. On for the wallet, so a key created on one
    ///   device is not stranded there. Off for session tokens, which are cheap to
    ///   mint again and have no business leaving the device that earned them.
    init(service: String = "com.recourse.buyer.keys", synchronizable: Bool = false) {
        self.service = service
        self.synchronizable = synchronizable
    }

    func save(_ data: Data, account: String) throws {
        SecItemDelete(matchQuery(account: account) as CFDictionary)

        var insert = baseQuery(account: account)
        insert[kSecValueData as String] = data
        insert[kSecAttrSynchronizable as String] = synchronizable
        // iCloud refuses to sync the ThisDeviceOnly classes, so a syncing item
        // settles for WhenUnlocked. It is still unreadable until the device is
        // unlocked; what it gives up is staying out of an encrypted backup.
        insert[kSecAttrAccessible as String] = synchronizable
            ? kSecAttrAccessibleWhenUnlocked
            : kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    func load(account: String) throws -> Data? {
        var query = matchQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let item = result as? [String: Any],
              let data = item[kSecValueData as String] as? Data else {
            throw KeychainError.unhandled(status)
        }

        // A wallet saved before this store synced is rewritten the first time it
        // is read, so existing installs reach the user's other devices instead
        // of staying pinned to the one that happened to create the key.
        if synchronizable, item[kSecAttrSynchronizable as String] as? Bool != true {
            try? save(data, account: account)
        }
        return data
    }

    func delete(account: String) throws {
        let status = SecItemDelete(matchQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Lookups match either kind. Without this a store that has switched to
    /// syncing cannot see, or delete, what it wrote before the switch.
    private func matchQuery(account: String) -> [String: Any] {
        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        return query
    }
}

protocol SecureDataStore: Actor {
    func save(_ data: Data, account: String) throws
    func load(account: String) throws -> Data?
    func delete(account: String) throws
}

extension KeychainStore: SecureDataStore {}

enum KeychainError: Error {
    case unhandled(OSStatus)
}
