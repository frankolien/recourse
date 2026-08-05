import SwiftUI
import UIKit

/// How this account signs in and how it comes back on a new phone. Everything
/// shown is live session state, not marketing copy: the provider is inferred
/// from the credential, and Apple credentials are checked against the system.
struct SignInRecoveryView: View {
    let accountSession: AccountSession
    var signer: (any BuyerSigner)?

    @State private var walletAddress: EthereumAddress?
    @State private var appleCredentialActive = false
    @State private var copiedAddress = false

    // The backend stores one opaque provider user id per account. Apple ids
    // carry dot-separated segments, Google subjects are all digits; that shape
    // is the only provider signal the client has.
    private var providerName: String {
        guard let id = accountSession.account?.providerUserID else { return "Recourse account" }
        if id.contains(".") { return "Sign in with Apple" }
        if !id.isEmpty, id.allSatisfy(\.isNumber) { return "Google account" }
        return "Email or passkey"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: providerName == "Sign in with Apple" ? "apple.logo" : "person.crop.circle.badge.checkmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(providerName)
                            .font(.recourse(14, .bold))
                            .foregroundStyle(RecourseColor.nightText)
                        Text(accountSession.account?.accountLabel ?? "Signed out")
                            .font(.recourse(12))
                            .foregroundStyle(RecourseColor.nightMuted)
                    }
                    Spacer()
                    if appleCredentialActive {
                        Text("Active")
                            .font(.recourse(11, .bold))
                            .foregroundStyle(RecourseColor.ledger)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("How you sign in")
            } footer: {
                Text("Your account lives on the Recourse backend. Signing in with the same provider on any iPhone restores your name, email, and payment history.")
            }

            Section {
                Button {
                    guard let walletAddress else { return }
                    UIPasteboard.general.string = walletAddress.value
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    copiedAddress = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedAddress = false
                    }
                } label: {
                    HStack {
                        Text(walletAddress?.value ?? "Generating…")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(RecourseColor.nightText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Image(systemName: copiedAddress ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(RecourseColor.ledger)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("This iPhone's wallet key")
            } footer: {
                Text("The signing key is generated on this device and never leaves it, so the testnet balance follows the phone rather than the account. A new phone gets a fresh key and a fresh wallet.")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    recoveryPoint("person.badge.key.fill", "Account: sign in again with \(providerName) and everything server-side comes back.")
                    recoveryPoint("iphone.gen3", "Wallet: the key is bound to this iPhone by design on testnet. Do not send funds here you cannot afford to lose with the phone.")
                    recoveryPoint("shield.checkered", "Protected payments are recorded on chain, so their verdicts and refunds survive any device.")
                }
                .padding(.vertical, 4)
            } header: {
                Text("If you lose this phone")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Sign-in & recovery")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            walletAddress = try? await signer?.address()
            if providerName == "Sign in with Apple",
               let userID = accountSession.account?.providerUserID {
                let checker = AppleCredentialStateChecker()
                appleCredentialActive = (try? await checker.credentialState(for: userID)) == .authorized
            }
        }
    }

    private func recoveryPoint(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .frame(width: 22)
            Text(text)
                .font(.recourse(12))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A per-payment cap enforced on this device before any transaction is signed,
/// in both the raw send flow and protected checkout.
struct PaymentLimitsView: View {
    @AppStorage(BuyerSettingKey.paymentLimitBaseUnits) private var limitBaseUnits = 0
    @State private var customText = ""
    @FocusState private var customFieldFocused: Bool

    private static let presets: [Int] = [50, 100, 250, 500, 1_000]

    var body: some View {
        List {
            Section {
                Toggle("Per-payment limit", isOn: limitEnabled)
                    .tint(RecourseColor.ledger)
                if limitBaseUnits > 0 {
                    HStack {
                        Text("Current limit")
                            .font(.recourse(14, .medium))
                            .foregroundStyle(RecourseColor.nightText)
                        Spacer()
                        Text(PaymentLimit.formatted(baseUnits: limitBaseUnits))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(RecourseColor.ledger)
                    }
                }
            } footer: {
                Text("Applies to sends and protected checkouts made from this iPhone. Payments above the limit are blocked before anything is signed.")
            }

            if limitBaseUnits > 0 {
                Section("Quick amounts") {
                    HStack(spacing: 8) {
                        ForEach(Self.presets, id: \.self) { preset in
                            let baseUnits = preset * Int(USDCAmount.base)
                            Button {
                                limitBaseUnits = baseUnits
                                customText = ""
                                customFieldFocused = false
                            } label: {
                                Text("\(preset)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(
                                        limitBaseUnits == baseUnits
                                            ? RecourseColor.ledger.opacity(0.28)
                                            : RecourseColor.nightChip,
                                        in: Capsule()
                                    )
                                    .foregroundStyle(
                                        limitBaseUnits == baseUnits
                                            ? RecourseColor.ledger
                                            : RecourseColor.nightText
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    HStack {
                        TextField("Custom amount", text: $customText)
                            .keyboardType(.decimalPad)
                            .focused($customFieldFocused)
                        Text("USDC")
                            .font(.recourse(12, .bold))
                            .foregroundStyle(RecourseColor.nightMuted)
                        if customAmount != nil {
                            Button("Set") {
                                if let customAmount {
                                    limitBaseUnits = Int(customAmount.baseUnits)
                                    customText = ""
                                    customFieldFocused = false
                                }
                            }
                            .font(.recourse(13, .bold))
                            .foregroundStyle(RecourseColor.ledger)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Payment limits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var customAmount: USDCAmount? {
        guard let amount = try? USDCAmount(decimalString: customText),
              amount.baseUnits > 0,
              amount.baseUnits <= UInt64(Int.max) else { return nil }
        return amount
    }

    private var limitEnabled: Binding<Bool> {
        Binding(
            get: { limitBaseUnits > 0 },
            set: { enabled in
                limitBaseUnits = enabled ? 250 * Int(USDCAmount.base) : 0
            }
        )
    }
}

/// Device-level behavior for the moment of payment.
struct PaymentPreferencesView: View {
    @AppStorage(BuyerSettingKey.confirmPaymentsWithBiometrics) private var confirmWithBiometrics = true

    var body: some View {
        List {
            Section {
                Toggle("Confirm payments with Face ID", isOn: $confirmWithBiometrics)
                    .tint(RecourseColor.ledger)
            } footer: {
                Text("Face ID gates this device's signing key at the moment of payment. Turning it off makes paying one tap faster; escrow protection and dispute rights are unaffected either way.")
            }

            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                        .frame(width: 22)
                    Text("Protected checkouts always escrow funds under the merchant's locked refund policy. There is no setting that weakens that; it is the product.")
                        .font(.recourse(12))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Payment preferences")
        .navigationBarTitleDisplayMode(.inline)
    }
}
