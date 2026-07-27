import SwiftUI
import UIKit

struct AccountFoundationView: View {
    let environment: AppEnvironment

    @AppStorage("recourse.hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("recourse.workspaceRole") private var storedWorkspaceRole = OnboardingRole.buyer.rawValue
    @AppStorage("recourse.appearance") private var appearanceRaw = "dark"
    @AppStorage(BuyerSettingKey.paymentLimitBaseUnits) private var limitBaseUnits = 0
    @State private var showsNameEditor = false
    @State private var walletAddress: EthereumAddress?
    @State private var copiedAddress = false
    @Environment(\.openURL) private var openURL

    private var configuration: AppConfiguration { environment.configuration }
    private var accountSession: AccountSession { environment.accountSession }

    // The account session is the single source of profile truth: names persist through
    // PUT /api/me/profile and come back on GET /api/me, so nothing profile-shaped lives
    // in local storage anymore.
    private var accountEmail: String? {
        accountSession.account?.email
    }

    private var accountName: String {
        accountSession.account?.displayName
            ?? accountEmail?.split(separator: "@").first.map(String.init)
            ?? "Recourse account"
    }

    var body: some View {
        List {
            identitySection
            appearanceSection
            securitySection
            generalSection
            supportSection
            aboutSection
            sessionSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showsNameEditor) {
            EditProfileNameView(
                givenName: accountSession.account?.givenName ?? "",
                familyName: accountSession.account?.familyName ?? "",
                accountSession: accountSession
            )
        }
        .task {
            walletAddress = try? await environment.buyerSigner.address()
        }
    }

    private var identitySection: some View {
        Section {
            Button {
                showsNameEditor = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(RecourseColor.ledger)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(accountName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(RecourseColor.nightText)
                            .lineLimit(1)
                        if let accountEmail {
                            Text(accountEmail)
                                .font(.system(size: 13))
                                .foregroundStyle(RecourseColor.nightMuted)
                                .lineLimit(1)
                        }
                        Label("Protected on \(configuration.chainName)", systemImage: "circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(RecourseColor.ledger)
                            .symbolRenderingMode(.monochrome)
                    }

                    Spacer()
                    Text("Edit")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // Applies to the in-app screens only; onboarding stays white and green
    // regardless of this choice.
    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearanceRaw) {
                Text("Dark").tag("dark")
                Text("Light").tag("light")
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
        }
    }

    private var securitySection: some View {
        Section("Security") {
            NavigationLink {
                SignInRecoveryView(
                    accountSession: accountSession,
                    signer: environment.buyerSigner
                )
            } label: {
                settingsRowLabel("Sign-in & recovery", "person.badge.key.fill")
            }
            deviceKeyRow
            NavigationLink {
                PaymentLimitsView()
            } label: {
                HStack {
                    settingsRowLabel("Payment limits", "gauge.with.dots.needle.67percent")
                    Spacer()
                    Text(limitBaseUnits > 0 ? PaymentLimit.formatted(baseUnits: limitBaseUnits) : "None")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }
        }
    }

    // The wallet is a per-device key, so payments and balance follow the device,
    // not the account. Showing the address here makes that split visible.
    private var deviceKeyRow: some View {
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
                settingsRowLabel("Device signing key", "iphone.gen3.radiowaves.left.and.right")
                Spacer()
                if copiedAddress {
                    Label("Copied", systemImage: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                } else if let walletAddress {
                    Text(walletAddress.shortened)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy this device's wallet address")
    }

    private var generalSection: some View {
        Section("General") {
            Button {
                showsNameEditor = true
            } label: {
                settingsRowLabel("Personal details", "person.crop.circle.fill")
            }
            .buttonStyle(.plain)
            NavigationLink {
                NotificationsSettingsView(paymentStore: environment.paymentStore)
            } label: {
                settingsRowLabel("Notifications", "bell.fill")
            }
            NavigationLink {
                PaymentPreferencesView()
            } label: {
                settingsRowLabel("Payment preferences", "creditcard.fill")
            }
            NavigationLink {
                AddressBookView(store: environment.addressBook)
            } label: {
                HStack {
                    settingsRowLabel("Address book", "person.crop.rectangle.stack.fill")
                    Spacer()
                    if !environment.addressBook.recipients.isEmpty {
                        Text("\(environment.addressBook.recipients.count)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(RecourseColor.nightMuted)
                    }
                }
            }
        }
    }

    private var supportSection: some View {
        Section("Support") {
            Button {
                openMail(subject: "Recourse support")
            } label: {
                settingsRow("Contact support", "message.fill")
            }
            .buttonStyle(.plain)
            Button {
                openMail(subject: "Recourse feedback")
            } label: {
                settingsRow("Share feedback", "star.bubble.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                settingsRowLabel("Network", "network")
                Spacer()
                Text(configuration.chainName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            HStack {
                settingsRowLabel("Version", "app.badge.checkmark")
                Spacer()
                Text(appVersion)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            Button {
                openURL(AppConfiguration.webAppURL.appending(path: "privacy"))
            } label: {
                settingsRow("Privacy", "hand.raised.fill")
            }
            .buttonStyle(.plain)
            Button {
                openURL(AppConfiguration.webAppURL.appending(path: "terms"))
            } label: {
                settingsRow("Terms", "doc.text.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private var sessionSection: some View {
        Section {
            // Mirror of the merchant workspace's "Switch to buyer": same account,
            // same wallet, the other side of the counter.
            Button("Switch to merchant") {
                storedWorkspaceRole = OnboardingRole.merchant.rawValue
            }
            .foregroundStyle(RecourseColor.ledger)

            Button("Replay onboarding") {
                hasCompletedOnboarding = false
                storedWorkspaceRole = ""
            }
            .foregroundStyle(RecourseColor.ledger)

            Button("Sign out", role: .destructive) {
                Task {
                    await accountSession.signOut()
                    hasCompletedOnboarding = false
                    storedWorkspaceRole = ""
                }
            }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // Mail first because replies need a reply-to address; the web support page
    // is the fallback for phones with no mail account configured.
    private func openMail(subject: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppConfiguration.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: "\n\nRecourse \(appVersion), iOS \(UIDevice.current.systemVersion)")
        ]
        guard let url = components.url else { return }
        openURL(url) { accepted in
            if !accepted {
                openURL(AppConfiguration.webAppURL.appending(path: "support"))
            }
        }
    }

    private func settingsRow(_ title: String, _ systemImage: String) -> some View {
        HStack {
            settingsRowLabel(title, systemImage)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.55))
        }
        .contentShape(Rectangle())
    }

    private func settingsRowLabel(_ title: String, _ systemImage: String) -> some View {
        Label {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(RecourseColor.nightText)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .frame(width: 26, height: 26)
        }
    }
}

private struct EditProfileNameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var givenName: String
    @State private var familyName: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    let accountSession: AccountSession

    init(
        givenName: String,
        familyName: String,
        accountSession: AccountSession
    ) {
        _givenName = State(initialValue: givenName)
        _familyName = State(initialValue: familyName)
        self.accountSession = accountSession
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $givenName)
                        .textContentType(.givenName)
                    TextField("Last name", text: $familyName)
                        .textContentType(.familyName)
                } header: {
                    Text("Your name")
                } footer: {
                    Text("Your name is saved to your Recourse account and appears on every device you sign in on.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(RecourseColor.ledger)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Personal details")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .tint(RecourseColor.ledger)
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(trimmed(givenName) == nil)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func trimmed(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        let failure = await accountSession.updateProfile(
            givenName: trimmed(givenName),
            familyName: trimmed(familyName)
        )
        isSaving = false
        if let failure {
            errorMessage = failure
        } else {
            dismiss()
        }
    }
}

#if DEBUG
#Preview("Settings") {
    NavigationStack {
        AccountFoundationView(environment: .preview())
    }
    .tint(RecourseColor.ledger)
}
#endif
