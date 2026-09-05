import SwiftUI
import UIKit

/// Settings, laid out the way the good money apps lay theirs out: who you are at the
/// top, then Security, General and About as plain rows with a coloured glyph each,
/// and the version at the bottom. The ground is flat; the rows are the structure.
struct AccountFoundationView: View {
    let environment: AppEnvironment

    @AppStorage("recourse.hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("recourse.workspaceRole") private var storedWorkspaceRole = OnboardingRole.buyer.rawValue
    @AppStorage("recourse.appearance") private var appearanceRaw = "dark"
    @AppStorage(BuyerSettingKey.paymentLimitBaseUnits) private var limitBaseUnits = 0
    @State private var showsNameEditor = false
    @State private var walletAddress: EthereumAddress?
    @State private var handle: String?
    @State private var copiedAddress = false
    @State private var presentedWebPage: WebPageLink?
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                profileCard
                section("Security") {
                    NavigationLink {
                        KeysView(environment: environment)
                    } label: {
                        row("Keys & recovery", "key.horizontal.fill", tint: Color(red: 0.55, green: 0.36, blue: 0.96))
                    }
                    NavigationLink {
                        SignInRecoveryView(accountSession: accountSession, signer: environment.buyerSigner)
                    } label: {
                        row("Sign-in & recovery", "person.badge.key.fill", tint: Color(red: 0.36, green: 0.45, blue: 0.93))
                    }
                    NavigationLink {
                        PaymentPreferencesView()
                    } label: {
                        row("Face ID for payments", "faceid", tint: RecourseColor.ledger)
                    }
                    NavigationLink {
                        PaymentLimitsView()
                    } label: {
                        row("Payment limits", "gauge.with.dots.needle.67percent", tint: Color(red: 0.23, green: 0.51, blue: 0.96),
                            value: limitBaseUnits > 0 ? PaymentLimit.formatted(baseUnits: limitBaseUnits) : "None")
                    }
                }
                section("General") {
                    NavigationLink {
                        ClaimHandleView(environment: environment)
                    } label: {
                        row("Your @handle", "at", tint: RecourseColor.ledger, value: handle.map { "@" + $0 })
                    }
                    Button {
                        showsNameEditor = true
                    } label: {
                        row("Personal details", "person.text.rectangle.fill", tint: Color(red: 0.13, green: 0.60, blue: 0.62))
                    }
                    .buttonStyle(.plain)
                    // Through the router like Home does, so the Team screens push their own
                    // routes onto the same path from here as from there.
                    Button {
                        environment.router.push(.team)
                    } label: {
                        row("Teams", "person.3.fill", tint: Color(red: 0.16, green: 0.62, blue: 0.80))
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        AddressBookView(store: environment.addressBook)
                    } label: {
                        row("Address book", "person.crop.rectangle.stack.fill", tint: Color(red: 0.94, green: 0.46, blue: 0.23),
                            value: environment.addressBook.recipients.isEmpty ? nil : "\(environment.addressBook.recipients.count)")
                    }
                    NavigationLink {
                        NotificationsSettingsView(paymentStore: environment.paymentStore)
                    } label: {
                        row("Notifications", "bell.fill", tint: Color(red: 0.93, green: 0.33, blue: 0.31))
                    }
                    appearanceRow
                }
                section("About") {
                    Button {
                        openMail(subject: "Recourse support")
                    } label: {
                        row("Contact support", "bubble.left.fill", tint: Color(red: 0.86, green: 0.30, blue: 0.78))
                    }
                    .buttonStyle(.plain)
                    Button {
                        openMail(subject: "Recourse feedback")
                    } label: {
                        row("Share your feedback", "star.bubble.fill", tint: Color(red: 0.30, green: 0.69, blue: 0.31))
                    }
                    .buttonStyle(.plain)
                    Button {
                        presentedWebPage = WebPageLink(url: AppConfiguration.webAppURL.appending(path: "privacy"))
                    } label: {
                        row("Privacy policy", "hand.raised.fill", tint: Color(red: 0.45, green: 0.47, blue: 0.50))
                    }
                    .buttonStyle(.plain)
                    Button {
                        presentedWebPage = WebPageLink(url: AppConfiguration.webAppURL.appending(path: "terms"))
                    } label: {
                        row("Terms", "doc.text.fill", tint: Color(red: 0.45, green: 0.47, blue: 0.50))
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task {
                            await accountSession.signOut()
                            hasCompletedOnboarding = false
                            storedWorkspaceRole = ""
                        }
                    } label: {
                        row("Sign out", "rectangle.portrait.and.arrow.right.fill", tint: Color(red: 0.93, green: 0.33, blue: 0.31), destructive: true)
                    }
                    .buttonStyle(.plain)
                }
                developerRows
                footer
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
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
        .sheet(item: $presentedWebPage) { page in
            SafariWebView(url: page.url)
                .ignoresSafeArea()
        }
        .task {
            walletAddress = try? await environment.buyerSigner.address()
            await loadHandle()
        }
    }

    // MARK: Top

    /// Who this is, in the slot other apps spend on an upsell: the name people pay,
    /// and the handle they pay it by.
    private var profileCard: some View {
        Button {
            showsNameEditor = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(RecourseColor.ledger)
                VStack(alignment: .leading, spacing: 3) {
                    Text(accountName)
                        .font(.recourse(16, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                        .lineLimit(1)
                    if let handle {
                        Text("@" + handle)
                            .font(.recourse(13, .medium))
                            .foregroundStyle(RecourseColor.ledger)
                            .lineLimit(1)
                    } else if let accountEmail {
                        Text(accountEmail)
                            .font(.recourse(13))
                            .foregroundStyle(RecourseColor.nightMuted)
                            .lineLimit(1)
                    }
                    Text("USDC on \(configuration.chainName)")
                        .font(.recourse(11, .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RecourseColor.nightText)
                    .frame(width: 30, height: 30)
                    .background(RecourseColor.night, in: Circle())
            }
            .padding(16)
            .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: Rows

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.recourse(14, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
                .padding(.top, 30)
                .padding(.bottom, 6)
            content()
        }
    }

    private func row(_ title: String, _ systemImage: String, tint: Color, value: String? = nil, destructive: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(.recourse(16, .medium))
                .foregroundStyle(destructive ? Color(red: 0.93, green: 0.33, blue: 0.31) : RecourseColor.nightText)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RecourseColor.nightMuted.opacity(0.7))
        }
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    // Applies to the in-app screens only; onboarding stays white and green
    // regardless of this choice.
    private var appearanceRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color(red: 0.45, green: 0.47, blue: 0.50), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("Appearance")
                .font(.recourse(16, .medium))
                .foregroundStyle(RecourseColor.nightText)
            Spacer(minLength: 8)
            Picker("Appearance", selection: $appearanceRaw) {
                Text("Dark").tag("dark")
                Text("Light").tag("light")
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
        .frame(height: 56)
    }

    /// The two switches a tester needs and a customer never sees the point of, kept
    /// small and last.
    private var developerRows: some View {
        HStack(spacing: 18) {
            Button("Switch to merchant") {
                storedWorkspaceRole = OnboardingRole.merchant.rawValue
            }
            Button("Replay onboarding") {
                hasCompletedOnboarding = false
                storedWorkspaceRole = ""
            }
        }
        .font(.recourse(12, .medium))
        .foregroundStyle(RecourseColor.nightMuted)
        .buttonStyle(.plain)
        .padding(.top, 34)
    }

    // The wallet is the account's address on Arc; shown where other apps print an
    // id, and copied with a tap, because support asks for it.
    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text("Recourse")
                    .font(.recourse(14, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Circle().fill(RecourseColor.ledger).frame(width: 6, height: 6)
            }
            Text("Version \(appVersion)")
                .font(.recourse(12, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
            if let walletAddress {
                Button {
                    UIPasteboard.general.string = walletAddress.value
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    copiedAddress = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedAddress = false
                    }
                } label: {
                    Text(copiedAddress ? "Copied" : walletAddress.value)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.nightMuted.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy this account's address")
            }
            HStack(spacing: 8) {
                Button("Privacy Policy") {
                    presentedWebPage = WebPageLink(url: AppConfiguration.webAppURL.appending(path: "privacy"))
                }
                Text("\u{00B7}")
                Button("Terms") {
                    presentedWebPage = WebPageLink(url: AppConfiguration.webAppURL.appending(path: "terms"))
                }
            }
            .font(.recourse(12))
            .foregroundStyle(RecourseColor.nightMuted)
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func loadHandle() async {
        let api = environment.makeHandleAPIClient()
        let existing = try? await accountSession.withAccessToken { token in
            try await api.myHandle(accessToken: token)
        }
        if let existing = existing ?? nil {
            handle = existing.handle
        }
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
                presentedWebPage = WebPageLink(url: AppConfiguration.webAppURL.appending(path: "support"))
            }
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
