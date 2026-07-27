import Foundation
import UserNotifications

/// Local notifications for closing dispute windows. Scheduled on-device from the
/// indexed payment list, so reminders work without any push infrastructure: the
/// deadline is known the moment the payment is, and missing it forfeits the
/// buyer's only enforcement path.
enum DisputeReminderScheduler {
    static let identifierPrefix = "dispute-deadline-"

    /// Six hours of lead time, clamped so a window closing sooner still gets a
    /// near-immediate reminder, and one closing within minutes gets none: a
    /// notification the buyer cannot act on is noise.
    static func reminderDate(protectionEnds: Date, now: Date) -> Date? {
        guard protectionEnds.timeIntervalSince(now) > 15 * 60 else { return nil }
        let sixHoursBefore = protectionEnds.addingTimeInterval(-6 * 3600)
        return max(now.addingTimeInterval(60), sixHoursBefore)
    }

    /// Replaces all pending dispute reminders with the current truth. Called
    /// after every buyer refresh so settled or disputed payments drop their
    /// reminders instead of firing stale ones.
    static func sync(payments: [DemoPayment], enabled: Bool, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard enabled else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else { return }

        for payment in payments where payment.state == .protected {
            guard let fireDate = reminderDate(protectionEnds: payment.protectionEnds, now: now) else {
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = "Dispute window closing"
            content.body = "\(payment.merchant): protection on \(payment.amountText) ends soon. Report a problem before the window closes."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: fireDate.timeIntervalSince(now),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: identifierPrefix + String(payment.id),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }
}
