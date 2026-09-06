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

    /// Where this phone stands with the server, so Settings can say it plainly
    /// instead of leaving a missing alert to guesswork.
    enum Registration: Equatable {
        /// Permission not asked, or no token yet.
        case none
        /// iOS has been asked for a token and has not answered.
        case waitingForToken
        case registered
        case failed(String)
    }
    private(set) var registration: Registration = .none

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
        PushBridge.shared.onFailure = { [weak self] reason in
            self?.registration = .failed(reason)
        }
        if let stamp = defaults.string(forKey: Self.uploadedKey), stamp.hasSuffix(":\(ActiveAccount.scope ?? "")") {
            registration = .registered
        }
    }

    /// Ask, then register. Returns whether alerts are allowed.
    @discardableResult
    /// Money arriving is the alert everyone wants, so the question is asked once the
    /// account is live, not only when someone joins a treasury.
    func enableAlerts() async -> Bool {
        await enableTeamAlerts()
    }

    func enableTeamAlerts() async -> Bool {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        authorization = status
        guard status == .authorized || status == .provisional || status == .ephemeral else { return false }
        if registration != .registered { registration = .waitingForToken }
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    /// Send the token again whatever was sent before: the way out when the server
    /// says it knows no phone for this account.
    func reregister() async {
        defaults.removeObject(forKey: Self.uploadedKey)
        registration = .none
        guard await enableAlerts() else { return }
        if let token = PushBridge.shared.latestToken { await upload(token) }
    }

    func refreshStatus() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// The token, once per account: the same token under the same account is not
    /// worth a request, and a token under a new account must be re-sent.
    private func upload(_ token: String) async {
        guard session.isAuthenticated else { return }
        let stamp = "\(token):\(ActiveAccount.scope ?? "")"
        guard defaults.string(forKey: Self.uploadedKey) != stamp else {
            // The server already has this token for this account.
            registration = .registered
            return
        }
        do {
            try await session.withAccessToken { try await api.register(token: token, environment: Self.environment, accessToken: $0) }
            defaults.set(stamp, forKey: Self.uploadedKey)
            registration = .registered
        } catch {
            // Next launch tries again; the token is still held by the bridge.
            registration = .failed(SmartAccountStore.describe(error))
        }
    }

    /// On sign-out: the phone should not hear about an account it no longer holds.
    func forget() async {
        defaults.removeObject(forKey: Self.uploadedKey)
        registration = .none
        guard let token = PushBridge.shared.latestToken else { return }
        try? await session.withAccessToken { try await api.unregister(token: token, accessToken: $0) }
    }
}
