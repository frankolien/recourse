import Foundation

/// Cross-process contract between the app and its widgets, stored in the shared app
/// group. The widget cannot reach the chain or the backend on its own schedule, so the
/// app drops this summary every time it refreshes and the widget renders the latest one.
///
/// It carries cheques rather than a balance because a balance on a home screen is a
/// number, and a cheque waiting to be cashed is a reason to open the app. The balance
/// rides along so the widget still says something when nothing is waiting.
struct WalletSnapshot: Codable, Sendable {
    var balanceBaseUnits: UInt64
    /// Cheques written to this account that could be cashed right now.
    var cashableBaseUnits: UInt64
    var cashableCount: Int
    /// When the soonest of those stops being cashable, so the widget can say how long
    /// is left rather than only how much.
    var nearestExpiry: Date?
    var updatedAt: Date

    static let appGroupID = "group.com.recourse.buyer"
    private static let storageKey = "recourse.wallet-snapshot"

    var balanceText: String { Self.money(balanceBaseUnits) }
    var cashableText: String { Self.money(cashableBaseUnits) }

    private static func money(_ baseUnits: UInt64) -> String {
        String(format: "$%.2f", Double(baseUnits) / 1_000_000)
    }

    static func load() -> WalletSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: storageKey)
        else { return nil }
        return try? JSONDecoder().decode(WalletSnapshot.self, from: data)
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = try? JSONEncoder().encode(self)
        else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
