import Foundation
import Observation
import UIKit
import UserNotifications

/// Team alerts: a proposal waiting for this account, a change scheduled that it can
/// veto. Asks for permission only when there is a treasury to hear about, sends the
/// phone's token to the server once per token, and forgets it on sign-out.
@MainActor
@Observable
final class PushCoordinator {
    private let session: AccountSession
    private let api: any PushAPI
    private let defaults: UserDefaults

    private(set) var authorization: UNAuthorizationStatus?

    /// Builds from Xcode reach Apple's sandbox gateway; TestFlight and the App Store
    /// reach production. The server needs to know which door to knock on.
    static let environment: String = {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }()

    private static let uploadedKey = "recourse.push.uploadedToken"

    init(session: AccountSession, api: any PushAPI, defaults: UserDefaults = .standard) {
        self.session = session
        self.api = api
        self.defaults = defaults
        PushBridge.shared.onToken = { [weak self] token in
            Task { await self?.upload(token) }
        }
    }

    /// Ask, then register. Returns whether alerts are allowed.
    @discardableResult
    func enableTeamAlerts() async -> Bool {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        authorization = status
        guard status == .authorized || status == .provisional || status == .ephemeral else { return false }
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    func refreshStatus() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// The token, once per account: the same token under the same account is not
    /// worth a request, and a token under a new account must be re-sent.
    private func upload(_ token: String) async {
        guard session.isAuthenticated else { return }
        let stamp = "\(token):\(ActiveAccount.scope ?? "")"
        guard defaults.string(forKey: Self.uploadedKey) != stamp else { return }
        do {
            try await session.withAccessToken { try await api.register(token: token, environment: Self.environment, accessToken: $0) }
            defaults.set(stamp, forKey: Self.uploadedKey)
        } catch {
            // Next launch tries again; the token is still held by the bridge.
        }
    }

    /// On sign-out: the phone should not hear about an account it no longer holds.
    func forget() async {
        defaults.removeObject(forKey: Self.uploadedKey)
        guard let token = PushBridge.shared.latestToken else { return }
        try? await session.withAccessToken { try await api.unregister(token: token, accessToken: $0) }
    }
}
