import XCTest
@testable import Recourse

/// The switch in Settings changes which account's money the app shows, so the pieces
/// that decide it are pinned here rather than trusted.
final class NetworkSelectionTests: XCTestCase {
    private func freshDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testAFreshInstallOpensOnATestnet() {
        // Opening a money app on real money by default is a decision nobody made.
        XCTAssertTrue(NetworkStore.resolved(freshDefaults()).isTestnet)
        XCTAssertEqual(Deployment.primary.chainID, Deployment.books[0].chainID)
    }

    func testTheBuildCarriesBothArcChains() {
        let ids = Set(Deployment.books.map(\.chainID))
        XCTAssertTrue(ids.contains(5042002), "Arc testnet")
        XCTAssertTrue(ids.contains(5042), "Arc mainnet")
    }

    func testOnlyArcMainnetIsNotATestnet() {
        for book in Deployment.books {
            XCTAssertEqual(book.isTestnet, book.chainID != 5042, "\(book.name)")
        }
    }

    func testAStoredChoiceSurvivesAndAnUnknownOneDoesNot() {
        let defaults = freshDefaults()
        let mainnet = Deployment.books.first { !$0.isTestnet }!
        NetworkStore.store(mainnet, in: defaults)
        XCTAssertEqual(NetworkStore.resolved(defaults).chainID, mainnet.chainID)

        // A build that no longer carries a chain must still open, which is the one case
        // where falling back silently is the right answer.
        defaults.set(NSNumber(value: UInt64(999_999)), forKey: NetworkStore.key)
        XCTAssertEqual(NetworkStore.resolved(defaults).chainID, Deployment.primary.chainID)
    }

    @MainActor
    func testSelectingTheChainYouAreOnDoesNothing() {
        // The caller signs the person out on a true answer, so a false one here is the
        // difference between a no-op tap and losing a session for nothing.
        let selection = NetworkSelection(defaults: freshDefaults())
        XCTAssertFalse(selection.select(selection.current))
        XCTAssertTrue(selection.select(selection.alternatives.first!))
    }

    /// One person is the same account on both chains. Without the chain in the cache
    /// path their play balance and their real balance share a file, and whichever wrote
    /// last is read as both.
    func testOneAccountGetsADifferentCacheOnEachChain() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let cache = SnapshotCache(root: root)
        let account = "the-same-person"

        let defaults = freshDefaults()
        let testnet = Deployment.books.first { $0.isTestnet }!
        let mainnet = Deployment.books.first { !$0.isTestnet }!

        NetworkStore.store(testnet, in: .standard)
        cache.save(["balance": "1000000"], key: "wallet", scope: account)
        NetworkStore.store(mainnet, in: .standard)
        cache.save(["balance": "5"], key: "wallet", scope: account)

        let onMainnet = cache.load([String: String].self, key: "wallet", scope: account)
        XCTAssertEqual(onMainnet?["balance"], "5")
        NetworkStore.store(testnet, in: .standard)
        let onTestnet = cache.load([String: String].self, key: "wallet", scope: account)
        XCTAssertEqual(onTestnet?["balance"], "1000000", "switching back finds what that chain knew")

        UserDefaults.standard.removeObject(forKey: NetworkStore.key)
        _ = defaults
        try? FileManager.default.removeItem(at: root)
    }
}
