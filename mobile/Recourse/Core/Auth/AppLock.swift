import Foundation
import LocalAuthentication
import Observation

/// Face ID before the app shows anything, so a phone left on a table does not show
/// its owner's money. On by default; Settings can turn it off. Locks at launch and
/// whenever the app comes back from the background.
@MainActor
@Observable
final class AppLock {
    private(set) var isLocked: Bool
    private(set) var isChecking = false
    private(set) var failureMessage: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLocked = Self.enabled(in: defaults)
    }

    static func enabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: BuyerSettingKey.lockOnOpen) == nil || defaults.bool(forKey: BuyerSettingKey.lockOnOpen)
    }

    var isEnabled: Bool { Self.enabled(in: defaults) }

    /// Called when the app leaves the foreground: the next return asks again.
    func lockIfEnabled() {
        guard isEnabled else { return }
        isLocked = true
    }

    /// Face ID, then the device passcode if Face ID is unavailable. A phone with
    /// neither has nothing to lock with, and the app opens.
    func unlock() async {
        guard isLocked, !isChecking else { return }
        isChecking = true
        failureMessage = nil
        defer { isChecking = false }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            isLocked = false
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Recourse")
            if ok { isLocked = false }
        } catch let error as LAError where error.code == .userCancel || error.code == .systemCancel || error.code == .appCancel {
            failureMessage = nil
        } catch {
            failureMessage = "Face ID did not recognise you. Try again."
        }
    }
}
