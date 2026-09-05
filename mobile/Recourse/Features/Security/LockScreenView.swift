import SwiftUI

/// What the app shows until Face ID says it is the owner. The same night palette
/// as the interior, with nothing of the account on it.
struct LockScreenView: View {
    let lock: AppLock

    var body: some View {
        ZStack {
            RecourseColor.night.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image("RecourseMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("Recourse is locked")
                    .font(.recourse(17, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                if let message = lock.failureMessage {
                    Text(message)
                        .font(.recourse(13))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button {
                    Task { await lock.unlock() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                        Text("Unlock")
                    }
                    .font(.recourse(16, .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(RecourseColor.night)
                .background(RecourseColor.ledger, in: Capsule())
                .disabled(lock.isChecking)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .task { await lock.unlock() }
    }
}
