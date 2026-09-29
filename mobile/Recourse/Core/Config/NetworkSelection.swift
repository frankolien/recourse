import Foundation

/// Which chain the app is pointed at, and the fact that changing it changes accounts.
///
/// This is not a display setting. A Safe on Arc testnet and a Safe on Arc mainnet are
/// different contracts holding different money, reached through different services that
/// issue their own sessions. Switching is closer to signing out of one product and into
/// another, and `SettingsNetworkRow` does exactly that: clears the session and every
/// cached figure before anything reads a balance again.
///
/// The choice lives in UserDefaults rather than the keychain or the snapshot cache, so
/// a reinstall returns to the safe default instead of restoring someone onto real money
/// they had forgotten they selected.
///
/// Resolution is deliberately nonisolated. `Deployment.usdc` and its neighbours are read
/// from background work all over the app, and binding the chain to the main actor would
/// make every one of those an await. The observable below exists for the UI to watch;
/// the value itself comes from `resolved()`.
enum NetworkStore {
    static let key = "network.chainID"

    /// The chain a caller should use right now.
    ///
    /// An unknown stored id means a build that no longer carries that chain, and
    /// falling back is right there: the alternative is an app that cannot open.
    static func resolved(_ defaults: UserDefaults = .standard) -> ChainBook {
        guard let stored = defaults.object(forKey: key) as? NSNumber,
              let book = Deployment.books.first(where: { $0.chainID == stored.uint64Value })
        else { return Deployment.primary }
        return book
    }

    static func store(_ book: ChainBook, in defaults: UserDefaults = .standard) {
        defaults.set(NSNumber(value: book.chainID), forKey: key)
    }
}

/// The UI's view of the same choice.
@MainActor
@Observable
final class NetworkSelection {
    static let shared = NetworkSelection()

    private let defaults: UserDefaults
    private(set) var current: ChainBook

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        current = NetworkStore.resolved(defaults)
    }

    var isTestnet: Bool { current.isTestnet }

    /// A build carrying one chain should not show a switch that cannot move.
    var canSwitch: Bool { Deployment.books.count > 1 }

    var alternatives: [ChainBook] { Deployment.books.filter { $0.chainID != current.chainID } }

    /// Point the app at another chain. False when it is already current, so a caller
    /// does not sign someone out to arrive where they already were.
    @discardableResult
    func select(_ book: ChainBook) -> Bool {
        guard book.chainID != current.chainID else { return false }
        NetworkStore.store(book, in: defaults)
        current = book
        return true
    }
}
