import UIKit
import UserNotifications

/// The one object UIKit talks to about pushes. It keeps nothing of its own: the
/// token goes to whoever asked for it, and a tapped alert goes to the router. Both
/// arrive before the app has built its environment, so each is held until claimed.
@MainActor
final class PushBridge: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = PushBridge()

    var onToken: ((String) -> Void)? {
        didSet { if let token = latestToken { onToken?(token) } }
    }
    var onRoute: ((AppRoute) -> Void)? {
        didSet {
            if let route = pendingRoute {
                pendingRoute = nil
                onRoute?(route)
            }
        }
    }
    private(set) var latestToken: String?
    private var pendingRoute: AppRoute?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        latestToken = token
        onToken?(token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // The simulator and a build without the entitlement land here. Alerts are
        // an extra, so the app carries on without them.
        print("push: registration failed: \(error.localizedDescription)")
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let route = userInfo["route"] as? [String: Any],
              route["kind"] as? String == "proposal",
              let account = route["account"] as? String,
              let txHash = route["txHash"] as? String else { return }
        await MainActor.run { deliver(.teamProposal(account: account, txHash: txHash)) }
    }

    private func deliver(_ route: AppRoute) {
        if let onRoute {
            onRoute(route)
        } else {
            pendingRoute = route
        }
    }
}
