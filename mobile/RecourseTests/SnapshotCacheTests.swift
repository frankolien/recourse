import XCTest
@testable import Recourse

/// What the app knew must survive a bad connection and a relaunch, per account.
final class SnapshotCacheTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appending(path: "snapshots-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testASnapshotRoundTripsAndStaysWithItsAccount() {
        let cache = SnapshotCache(root: root)
        let transfer = TokenTransfer(hash: "0xabc", blockNumber: 7, timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                                     from: "0xaa", to: "0xbb", value: 1_250_000, token: "0xusdc", symbol: "USDC", method: "transfer")

        cache.save([transfer], key: "history", scope: "apple:frank")

        XCTAssertEqual(cache.load([TokenTransfer].self, key: "history", scope: "apple:frank"), [transfer])
        XCTAssertNil(cache.load([TokenTransfer].self, key: "history", scope: "apple:someone-else"))
        XCTAssertNil(cache.load([TokenTransfer].self, key: "history", scope: nil))

        cache.remove(key: "history", scope: "apple:frank")
        XCTAssertNil(cache.load([TokenTransfer].self, key: "history", scope: "apple:frank"))
    }

    @MainActor
    func testHistoryKeepsItsRowsWhenTheExplorerFails() async {
        let scope = signIn()
        defer { ActiveAccount.set(nil) }
        let cache = SnapshotCache(root: root)
        let explorer = ScriptedExplorer(answers: [.success([transfer()]), .failure(ExplorerAPIError.invalidResponse)])
        let history = TransferHistory(configuration: .live, signer: FixtureSigner(), explorer: explorer, cache: cache)

        await history.refresh(force: true)
        XCTAssertEqual(history.transfers.count, 1)
        XCTAssertNil(history.errorMessage)

        await history.refresh(force: true)
        XCTAssertEqual(history.transfers.count, 1, "a failed read must not empty the list")
        XCTAssertNotNil(history.errorMessage)
        XCTAssertEqual(history.me, FixtureSigner.address.lowercased())
        _ = scope
    }

    @MainActor
    func testAFreshHistoryOpensOnItsSnapshotBeforeTheNetworkAnswers() async {
        _ = signIn()
        defer { ActiveAccount.set(nil) }
        let cache = SnapshotCache(root: root)
        let first = TransferHistory(configuration: .live, signer: FixtureSigner(), explorer: ScriptedExplorer(answers: [.success([transfer()])]), cache: cache)
        await first.refresh(force: true)

        // A relaunch on a bad connection: a new store, an explorer that never answers.
        let second = TransferHistory(configuration: .live, signer: FixtureSigner(), explorer: ScriptedExplorer(answers: [.failure(ExplorerAPIError.invalidResponse)]), cache: cache)
        await second.refresh(force: true)

        XCTAssertEqual(second.transfers, first.transfers)
        XCTAssertEqual(second.me, first.me)
        XCTAssertNotNil(second.errorMessage)
    }

    @MainActor
    func testAnotherAccountNeverSeesTheLastPersonsRows() async {
        _ = signIn(id: "one")
        let cache = SnapshotCache(root: root)
        let history = TransferHistory(configuration: .live, signer: FixtureSigner(), explorer: ScriptedExplorer(answers: [.success([transfer()]), .failure(ExplorerAPIError.invalidResponse)]), cache: cache)
        await history.refresh(force: true)
        XCTAssertEqual(history.transfers.count, 1)

        _ = signIn(id: "two")
        defer { ActiveAccount.set(nil) }
        await history.refresh(force: true)

        XCTAssertTrue(history.transfers.isEmpty)
    }

    // MARK: Fixtures

    // The scope is the account id, so a different person needs a different id.
    @discardableResult
    private func signIn(id: String = "frank") -> String? {
        let accountID = Int64(id.utf8.reduce(0) { $0 &+ Int($1) })
        ActiveAccount.set(AuthenticatedAccount(accountID: accountID, providerUserID: "apple-\(id)", email: "\(id)@example.com", givenName: nil, familyName: nil))
        return ActiveAccount.scope
    }

    private func transfer() -> TokenTransfer {
        TokenTransfer(hash: "0xabc", blockNumber: 1, timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                      from: FixtureSigner.address.lowercased(), to: "0x9965507d1a55bcc2695c58ba16fb37d819b0a4dc",
                      value: 1_000_000, token: "0x3600000000000000000000000000000000000000", symbol: "USDC", method: "transfer")
    }
}

private actor ScriptedExplorer: ExplorerAPI {
    private var answers: [Result<[TokenTransfer], Error>]

    init(answers: [Result<[TokenTransfer], Error>]) {
        self.answers = answers
    }

    func tokenTransfers(for address: EthereumAddress) async throws -> [TokenTransfer] {
        guard !answers.isEmpty else { throw ExplorerAPIError.invalidResponse }
        return try answers.removeFirst().get()
    }
}

private actor FixtureSigner: BuyerSigner {
    static let address = "0x1111111111111111111111111111111111111111"

    func address() async throws -> EthereumAddress {
        EthereumAddress(trusted: Self.address)
    }

    func sign(_ transaction: UnsignedTransaction) async throws -> Data {
        throw BuyerSignerError.signingFailed
    }

    func signEIP712(_ typedData: Data) async throws -> Data {
        throw BuyerSignerError.signingFailed
    }

    func reset() async throws {}
}
