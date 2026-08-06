import XCTest
@testable import Recourse

/// These run against the real keychain rather than a double, because the thing
/// worth proving is that the system accepts what the store asks it for. A
/// synchronizable item that fails to add would take wallet creation down with it.
final class KeychainStoreTests: XCTestCase {
    private let service = "com.recourse.tests.keychain"

    func testSynchronizableItemRoundTrips() async throws {
        let store = KeychainStore(service: service, synchronizable: true)
        let account = "sync-round-trip"
        try await store.delete(account: account)
        defer { Task { try? await store.delete(account: account) } }

        try await store.save(Data("keystore".utf8), account: account)
        let loaded = try await store.load(account: account)
        XCTAssertEqual(loaded, Data("keystore".utf8))

        try await store.delete(account: account)
        let afterDelete = try await store.load(account: account)
        XCTAssertNil(afterDelete)
    }

    func testSyncingStoreAdoptsAnItemWrittenBeforeSyncingWasOn() async throws {
        let account = "sync-migration"
        let deviceOnly = KeychainStore(service: service, synchronizable: false)
        let syncing = KeychainStore(service: service, synchronizable: true)
        try await deviceOnly.delete(account: account)
        try await syncing.delete(account: account)
        defer { Task { try? await syncing.delete(account: account) } }

        try await deviceOnly.save(Data("existing wallet".utf8), account: account)

        // The wallet an install already holds has to survive the switch; losing
        // it here would mean losing the funds it controls.
        let found = try await syncing.load(account: account)
        XCTAssertEqual(found, Data("existing wallet".utf8))

        // And the read should have upgraded it in place, so it now syncs.
        let stillThere = try await syncing.load(account: account)
        XCTAssertEqual(stillThere, Data("existing wallet".utf8))
    }

    func testDeviceOnlyAndSyncingStoresDoNotCollideAcrossServices() async throws {
        let account = "isolation"
        let wallet = KeychainStore(service: service + ".wallet", synchronizable: true)
        let session = KeychainStore(service: service + ".session", synchronizable: false)
        try await wallet.delete(account: account)
        try await session.delete(account: account)
        defer {
            Task {
                try? await wallet.delete(account: account)
                try? await session.delete(account: account)
            }
        }

        try await wallet.save(Data("key".utf8), account: account)
        try await session.save(Data("token".utf8), account: account)

        let walletValue = try await wallet.load(account: account)
        let sessionValue = try await session.load(account: account)
        XCTAssertEqual(walletValue, Data("key".utf8))
        XCTAssertEqual(sessionValue, Data("token".utf8))
    }
}
