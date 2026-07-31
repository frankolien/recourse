import Foundation

/// Cross-process contract between the app and its widgets, stored in the
/// shared app group. The widget cannot reach the chain or the backend on its
/// own schedule, so the app drops this summary every time it refreshes and
/// the widget renders whatever the latest drop says.
struct ProtectionSnapshot: Codable, Sendable {
    var protectedBaseUnits: UInt64
    var activeCount: Int
    var nearestDeadline: Date?
    var updatedAt: Date

    static let appGroupID = "group.com.recourse.buyer"
    private static let storageKey = "recourse.protection-snapshot"

    var protectedText: String {
        String(format: "$%.2f", Double(protectedBaseUnits) / 1_000_000)
    }

    static func load() -> ProtectionSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: storageKey)
        else { return nil }
        return try? JSONDecoder().decode(ProtectionSnapshot.self, from: data)
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = try? JSONEncoder().encode(self)
        else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
