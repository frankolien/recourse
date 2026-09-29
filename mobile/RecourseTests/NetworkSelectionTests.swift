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
        defer { try? FileManager.default.removeItem(at: root) }
        let account = "the-same-person"
        let testnet = SnapshotCache(chainID: 5042002, root: root)
        let mainnet = SnapshotCache(chainID: 5042, root: root)

        testnet.save(["balance": "1000000"], key: "wallet", scope: account)
        mainnet.save(["balance": "5"], key: "wallet", scope: account)

        XCTAssertEqual(mainnet.load([String: String].self, key: "wallet", scope: account)?["balance"], "5")
        XCTAssertEqual(testnet.load([String: String].self, key: "wallet", scope: account)?["balance"], "1000000",
                       "switching back finds what that chain knew")
    }

    /// The race that put testnet euros on mainnet. A store built for one chain is still
    /// finishing a read when the person switches; when it writes, it must write under
    /// the chain it was built for, not the one the app is on now. The cache carries its
    /// chain from construction, so where it writes cannot depend on when it writes.
    func testAStoreThatOutlivesASwitchStillWritesToItsOwnChain() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = "the-same-person"
        let oldStoresCache = SnapshotCache(chainID: 5042002, root: root)
        let newStoresCache = SnapshotCache(chainID: 5042, root: root)

        // The switch happens, then the old store's read lands and it saves.
        oldStoresCache.save(["eurc": "20000000"], key: "balance", scope: account)

        XCTAssertNil(newStoresCache.load([String: String].self, key: "balance", scope: account),
                     "the new chain must not see the old chain's late write")
    }
}

/// The pieces that make switching safe rather than merely possible.
extension NetworkSelectionTests {
    func testEachChainKeepsItsOwnSessionSlot() {
        let testnet = Deployment.books.first { $0.isTestnet }!
        let mainnet = Deployment.books.first { !$0.isTestnet }!
        let a = AccountSessionStore.slot(for: testnet.chainID)
        let b = AccountSessionStore.slot(for: mainnet.chainID)
        XCTAssertNotEqual(a, b, "a session issued by one chain's service is worth nothing to another's")
    }

    func testThePrimaryChainKeepsTheOriginalSlotName() {
        // Renaming it would sign out everyone already testing, to fix a problem they
        // do not have.
        XCTAssertEqual(AccountSessionStore.slot(for: Deployment.primary.chainID), "backend-account-session")
    }

    func testEveryChainHasItsOwnServiceAndEndpoint() {
        // Two chains sharing an API URL would mean one database answering for both,
        // and a balance from the wrong one.
        let apis = Deployment.books.map(\.apiURL)
        XCTAssertEqual(Set(apis).count, apis.count, "each chain needs its own service")
        let rpcs = Deployment.books.map(\.rpcURL)
        XCTAssertEqual(Set(rpcs).count, rpcs.count, "each chain needs its own endpoint")
    }

    @MainActor
    func testTheConfigurationFollowsTheChain() {
        for book in Deployment.books {
            let configuration = AppConfiguration.of(book)
            XCTAssertEqual(configuration.chainID, book.chainID)
            XCTAssertEqual(configuration.apiURL.absoluteString, book.apiURL)
            XCTAssertEqual(configuration.chainName, book.name)
            // A chain with no venue must not inherit another chain's.
            if book.fxRouter == nil { XCTAssertNil(configuration.fxRouterAddress) }
        }
    }
}
