import SwiftUI

/// Someone is trying to replace one of this account's keys.
///
/// Both key changes need two of the three keys, so both are things a person who has
/// taken an inbox and one other thing can start. Neither runs immediately any more,
/// and this is the reason the wait exists: whoever still holds a key gets told, and
/// gets one button that ends it.
///
/// It sits at the bottom of the screen rather than above the balance. The earlier
/// version was a full card per request, which pushed the balance off the first screen
/// and stacked into a wall when two requests were open at once. Alarm is still the
/// right tone, but a thing that hides the balance to warn you about the balance is
/// working against itself. So: one bar per key being replaced, where the thumb
/// already is, never dismissible.
///
/// Takes the whole group for one key rather than one request, because two rows saying
/// the same sentence teach the reader nothing, and stopping a recovery means stopping
/// every request against that key, not the first one somebody happened to tap.
struct PendingRecoveryBanner: View {
    let environment: AppEnvironment
    /// All pending requests against one key. Never empty.
    let group: [PendingRecovery]
    let onStopped: () -> Void

    @State private var stopping = false
    @State private var failure: String?
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Someone is recovering your account")
                        .font(.recourse(13, .semibold))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.recourse(11.5, .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .contentTransition(.numericText())
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                Spacer(minLength: 6)

                Button(action: stop) {
                    Group {
                        if stopping {
                            ProgressView().tint(RecourseColor.ledger).scaleEffect(0.8)
                        } else {
                            Text("Stop")
                                .font(.recourse(13, .semibold))
                        }
                    }
                    .frame(minWidth: 58)
                    .frame(height: 34)
                    .background(.white, in: Capsule())
                    .foregroundStyle(RecourseColor.ledger)
                }
                .buttonStyle(.plain)
                .disabled(stopping)
            }

            // Only when it has gone wrong. The reassurance that this might be you
            // lives on the security screen; a bar this size has room for one idea.
            if let failure {
                Text(failure)
                    .font(.recourse(11, .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(red: 0.62, green: 0.16, blue: 0.11), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onReceive(clock) { now = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Someone is recovering your account. \(detail)")
    }

    private var first: PendingRecovery { group[0] }

    /// What is changing, when it lands, and how many requests are open, in one line.
    private var detail: String {
        var parts = ["\(first.whatIsChanging) · \(countdown)"]
        if group.count > 1 {
            parts.append("\(group.count) requests")
        }
        return parts.joined(separator: " · ")
    }

    /// Time is the whole product here, so it is counted down rather than stated once.
    /// The soonest of the group, because that is the one that decides the deadline.
    private var countdown: String {
        guard let ready = group.compactMap(\.ready).min() else { return "Waiting" }
        let left = Int(ready.timeIntervalSince(now))
        guard left > 0 else { return "The wait is over" }
        let hours = left / 3600
        let minutes = (left % 3600) / 60
        let seconds = left % 60
        return hours > 0
            ? String(format: "Goes through in %dh %02dm", hours, minutes)
            : String(format: "Goes through in %02dm %02ds", minutes, seconds)
    }

    /// Stops every request against this key. One of them failing stops the rest from
    /// being attempted, because a partial stop that reports success would be a lie.
    private func stop() {
        stopping = true
        failure = nil
        Task {
            do {
                for pending in group {
                    try await environment.smartAccounts.stopRecovery(pending)
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onStopped()
            } catch {
                failure = (error as? SmartAccountAPIError)?.message ?? "That did not go through. Try again."
            }
            stopping = false
        }
    }
}
