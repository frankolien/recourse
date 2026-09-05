import SwiftUI

/// Moves the account's Device Key onto this phone after the old one is gone.
///
/// The old phone's key cannot be copied, so this makes a new one here and swaps it
/// into the account. That swap needs two of three, and the one missing is the Device
/// Key itself, so the pair is the Cloud Key on this phone and the Recovery Key, which
/// the emailed code releases.
struct RestoreDeviceView: View {
    let environment: AppEnvironment

    private enum Stage: Equatable {
        case explain
        case code(sentTo: String)
        case working(String)
        case done(DeviceRotationOutcome)
    }

    @State private var stage: Stage = .explain
    @State private var code = ""
    @State private var problem: String?
    @State private var hasCloudKey = true
    @FocusState private var codeFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var store: SmartAccountStore { environment.smartAccounts }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch stage {
                case .explain:
                    header("Restore this phone", "Your account is on another phone. Bring it here.")
                    if hasCloudKey {
                        steps
                        action("Email me a code") { await sendCode() }
                    } else {
                        cloudKeyMissing
                    }
                case .code(let sentTo):
                    header("Confirm email", "The code has been sent to \(sentTo).")
                    codeField
                    action("Restore") { await restore() }
                    Button("Send another code") { Task { await sendCode() } }
                        .font(.recourse(13, .semibold))
                        .foregroundStyle(RecourseColor.nightMuted)
                case .working(let message):
                    header("Restoring", message)
                    ProgressView().tint(RecourseColor.nightText).frame(maxWidth: .infinity).padding(.top, 30)
                case .done(let outcome):
                    header("This phone is your Device Key", "The swap went through on Arc.")
                    Text(outcome.txHash)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    action("Done") { dismiss() }
                }
                if let problem { note(problem) }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RecourseColor.night)
        .navigationTitle("Restore")
        .navigationBarTitleDisplayMode(.inline)
        .task { hasCloudKey = await environment.switchableSigner.cloud.hasWallet() }
    }

    // MARK: Stages

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step("envelope.fill", "We email you a code", "It proves the inbox on your account is yours.")
            step("faceid", "This phone gets its own key", "A new Device Key, made here and held by this phone alone.")
            step("arrow.triangle.2.circlepath", "Your Cloud Key approves the swap", "Two keys sign it: the one in your iCloud and the recovery key the code unlocks.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var cloudKeyMissing: some View {
        VStack(alignment: .leading, spacing: 14) {
            step("icloud.slash", "Your Cloud Key is not on this phone", "It arrives with iCloud Keychain on your own iPhones. On any other device, restore it from your recovery PIN first.")
            NavigationLink {
                WalletRecoveryView(environment: environment)
            } label: {
                Text("Restore Cloud Key with PIN")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var codeField: some View {
        TextField("6-digit code", text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($codeFocused)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .kerning(6)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear { codeFocused = true }
    }

    // MARK: Actions

    private func sendCode() async {
        problem = nil
        do {
            let issued = try await store.requestRecoveryCode()
            code = ""
            stage = .code(sentTo: issued.sentTo)
        } catch {
            problem = describe(error)
        }
    }

    private func restore() async {
        problem = nil
        let entered = code.trimmingCharacters(in: .whitespaces)
        guard entered.count == 6 else {
            problem = "Enter the six digits from the email."
            return
        }
        stage = .working("Checking the code")
        do {
            let grant = try await store.verifyRecoveryCode(entered)
            stage = .working("Making this phone's key and swapping it in")
            let outcome = try await store.restoreDevice(grantID: grant.grantId)
            stage = .done(outcome)
        } catch {
            problem = describe(error)
            stage = .code(sentTo: "your email")
        }
    }

    private func describe(_ error: Error) -> String {
        SmartAccountStore.describe(error)
    }

    // MARK: Pieces

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.recourse(24, .bold))
                .foregroundStyle(RecourseColor.nightText)
            Text(detail)
                .font(.recourse(13))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.recourse(14, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(body)
                    .font(.recourse(12))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func action(_ title: String, _ work: @escaping () async -> Void) -> some View {
        Button {
            Task { await work() }
        } label: {
            Text(title)
                .font(.recourse(15, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RecourseColor.ledger, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.recourse(12, .medium))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
