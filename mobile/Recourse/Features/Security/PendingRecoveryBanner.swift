import SwiftUI

/// Someone is trying to replace one of this account's keys.
///
/// Both key changes need two of the three keys, so both are things a person who has
/// taken an inbox and one other thing can start. Neither runs immediately any more,
/// and this is the reason the wait exists: whoever still holds a key gets told, and
/// gets one button that ends it.
///
/// It is deliberately loud. Everything else in the app is calm; this is the one
/// screen where alarm is the correct tone, because the honest reading of it is that
/// the account is being taken.
struct PendingRecoveryBanner: View {
    let environment: AppEnvironment
    let pending: PendingRecovery
    let onStopped: () -> Void

    @State private var stopping = false
    @State private var failure: String?
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Someone is recovering your account")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("\(pending.whatIsChanging) is being replaced.")
                    .font(.recourse(13, .medium))
                    .foregroundStyle(.white.opacity(0.92))
                Text(countdown)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            Text("If this is you, there is nothing to do. If it is not, stop it now and change your email password.")
                .font(.recourse(11.5, .medium))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            if let failure {
                Text(failure)
                    .font(.recourse(11.5, .medium))
                    .foregroundStyle(.white)
            }

            Button(action: stop) {
                Group {
                    if stopping {
                        ProgressView().tint(RecourseColor.ledger)
                    } else {
                        Text("Stop this")
                            .font(.recourse(14, .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(.white, in: Capsule())
                .foregroundStyle(RecourseColor.ledger)
            }
            .buttonStyle(.plain)
            .disabled(stopping)
        }
        .padding(16)
        .background(Color(red: 0.62, green: 0.16, blue: 0.11), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onReceive(clock) { now = $0 }
        .accessibilityElement(children: .contain)
    }

    /// Time is the whole product here, so it is counted down rather than stated once.
    private var countdown: String {
        guard let ready = pending.ready else { return "Waiting" }
        let left = Int(ready.timeIntervalSince(now))
        guard left > 0 else { return "The wait is over" }
        let hours = left / 3600
        let minutes = (left % 3600) / 60
        let seconds = left % 60
        return hours > 0
            ? String(format: "Goes through in %dh %02dm", hours, minutes)
            : String(format: "Goes through in %02dm %02ds", minutes, seconds)
    }

    private func stop() {
        stopping = true
        failure = nil
        Task {
            do {
                try await environment.smartAccounts.stopRecovery(pending)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onStopped()
            } catch {
                failure = (error as? SmartAccountAPIError)?.message ?? "That did not go through. Try again."
            }
            stopping = false
        }
    }
}
