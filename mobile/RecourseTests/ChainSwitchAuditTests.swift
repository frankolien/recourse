import XCTest
@testable import Recourse

/// The rules found by auditing what a chain-specific number can survive across a
/// switch. Each one was a real leak on 2026-09-29, when testnet euros showed on
/// mainnet, and each is pinned here so it cannot come back quietly.
final class ChainSwitchAuditTests: XCTestCase {
    private var mainnet: ChainBook { Deployment.books.first { !$0.isTestnet }! }
    private var testnet: ChainBook { Deployment.books.first { $0.isTestnet }! }

    // MARK: Euros

    /// The reader answers nil on a chain with no EURC. That nil is an answer, and the
    /// figure on screen came from the last chain that had euros, so it must not win.
    func testNoEurosOnAChainWithoutEURC_EvenWhenAFigureIsOnScreen() {
        let stale = EURCAmount(baseUnits: UInt64(20_000_000))
        XCTAssertNil(BuyerPaymentStore.euros(read: .success(nil), chainHasEURC: false, previous: stale))
        XCTAssertNil(BuyerPaymentStore.euros(read: .failure(URLError(.timedOut)), chainHasEURC: false, previous: stale))
    }

    /// On a chain that has euros, a failed read keeps the last figure: blanking a
    /// balance on a bad connection is the thing a money app must never do.
    func testAFailedEuroReadKeepsTheLastFigureOnlyWhereEurosExist() {
        let last = EURCAmount(baseUnits: UInt64(20_000_000))
        XCTAssertEqual(BuyerPaymentStore.euros(read: .failure(URLError(.timedOut)), chainHasEURC: true, previous: last), last)
        let fresh = EURCAmount(baseUnits: UInt64(5))
        XCTAssertEqual(BuyerPaymentStore.euros(read: .success(fresh), chainHasEURC: true, previous: last), fresh)
    }

    // MARK: Explorer and bundler

    func testMainnetHasNoQueryableExplorerAndSaysSo() {
        // explorer.arc.io answers an app with a Cloudflare challenge, checked 2026-09-29.
        XCTAssertNil(mainnet.explorerAPIURL)
        XCTAssertNotNil(testnet.explorerAPIURL)
        XCTAssertNotEqual(AppConfiguration.of(mainnet).explorerPageURL, AppConfiguration.of(testnet).explorerPageURL,
                          "a transaction link must open on its own chain's explorer")
    }

    /// Pimlico's endpoint names the chain in its path. The testnet endpoint would take
    /// a mainnet operation's bytes and submit them to the wrong chain.
    func testTheBundlerNamesTheChainItIsFor() {
        for book in Deployment.books {
            let url = AppConfiguration.of(book).bundlerURL.absoluteString
            XCTAssertTrue(url.contains("/\(book.chainID)/"), "\(book.name): \(url)")
        }
        XCTAssertNotEqual(AppConfiguration.of(mainnet).bundlerURL, AppConfiguration.of(testnet).bundlerURL)
    }

    // MARK: History

    /// Asking another chain's explorer would answer about another chain's money. With
    /// no explorer the rows stay whatever this chain's own snapshot held and the
    /// screen says why.
    @MainActor
    func testHistoryWithoutAnExplorerSaysSoAndKeepsItsRows() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = TransferHistory(
            configuration: AppConfiguration.of(mainnet),
            signer: AuditFixtureSigner(),
            explorer: nil,
            cache: SnapshotCache(chainID: mainnet.chainID, root: root)
        )
        XCTAssertTrue(history.isUnavailable)
        await history.refresh(force: true)
        XCTAssertTrue(history.transfers.isEmpty)
        XCTAssertEqual(history.errorMessage, "History is not available on \(mainnet.name) yet.")
    }
}

extension ChainSwitchAuditTests {
    /// The racy build could have filed another chain's rows under mainnet. On a chain
    /// with no explorer nothing could have written rows legitimately, so whatever is on
    /// disk is not read, however it got there.
    @MainActor
    func testHistoryWithoutAnExplorerIgnoresAnySnapshotOnDisk() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SnapshotCache(chainID: mainnet.chainID, root: root)
        // Poison: rows filed under mainnet by something that should not have.
        struct Poison: Codable { let me: String?; let transfers: [TokenTransfer] }
        let stray = TokenTransfer(
            hash: "0xabc", blockNumber: 1, timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            from: "0x000000000000000000000000000000000000dead", to: "0x1111111111111111111111111111111111111111",
            value: 1_000_000, token: "0x3600000000000000000000000000000000000000", symbol: "USDC", method: "transfer"
        )
        cache.save(Poison(me: "0x000000000000000000000000000000000000dead", transfers: [stray]), key: "history", scope: ActiveAccount.scope)
        // The poison must be real, or the assertion below proves nothing.
        XCTAssertEqual(cache.load(Poison.self, key: "history", scope: ActiveAccount.scope)?.transfers.count, 1)

        let history = TransferHistory(
            configuration: AppConfiguration.of(mainnet),
            signer: AuditFixtureSigner(),
            explorer: nil,
            cache: cache
        )
        await history.refresh(force: true)
        XCTAssertTrue(history.transfers.isEmpty, "rows that no explorer could have produced must not be shown")
    }
}

private actor AuditFixtureSigner: BuyerSigner {
    func address() async throws -> EthereumAddress {
        EthereumAddress(trusted: "0x000000000000000000000000000000000000dEaD")
    }
    func sign(_ transaction: UnsignedTransaction) async throws -> Data { throw BuyerSignerError.signingFailed }
    func signEIP712(_ typedData: Data) async throws -> Data { throw BuyerSignerError.signingFailed }
    func reset() async throws {}
}
