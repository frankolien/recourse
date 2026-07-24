import SwiftUI

struct AccountFoundationView: View {
    let configuration: AppConfiguration
    let accountSession: AccountSession

    @AppStorage("recourse.hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("recourse.workspaceRole") private var storedWorkspaceRole = OnboardingRole.buyer.rawValue
    @AppStorage("recourse.profile.givenName") private var storedGivenName = ""
    @AppStorage("recourse.profile.familyName") private var storedFamilyName = ""
    @State private var showsNameEditor = false

    private var accountEmail: String {
        accountSession.account?.email ?? "frank@recourse.app"
    }

    private var accountName: String {
        let storedName = [storedGivenName, storedFamilyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return nonEmpty(storedName)
            ?? accountSession.account?.displayName
            ?? accountEmail.split(separator: "@").first.map(String.init)
            ?? "Frank"
    }

    private var initialGivenName: String {
        nonEmpty(storedGivenName)
            ?? accountSession.account?.givenName
            ?? accountName.split(separator: " ").first.map(String.init)
            ?? ""
    }

    private var initialFamilyName: String {
        nonEmpty(storedFamilyName)
            ?? accountSession.account?.familyName
            ?? accountName.split(separator: " ").dropFirst().joined(separator: " ")
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        List {
            identitySection
            securitySection
            generalSection
            supportSection
            aboutSection
            sessionSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showsNameEditor) {
            EditProfileNameView(
                givenName: initialGivenName,
                familyName: initialFamilyName
            ) { givenName, familyName in
                storedGivenName = givenName
                storedFamilyName = familyName
            }
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
                            .foregroundStyle(RecourseColor.ink)
                            .lineLimit(1)
                        Text(accountEmail)
                            .font(.system(size: 13))
                            .foregroundStyle(RecourseColor.muted)
                            .lineLimit(1)
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

    private var securitySection: some View {
        Section("Security") {
            settingsRow("Passkeys & recovery", "person.badge.key.fill")
            settingsRow("Device signing key", "iphone.gen3.radiowaves.left.and.right")
            settingsRow("Payment limits", "gauge.with.dots.needle.67percent")
        }
    }

    private var generalSection: some View {
        Section("General") {
            Button {
                showsNameEditor = true
            } label: {
                settingsRowLabel("Personal details", "person.crop.circle.fill")
            }
            .buttonStyle(.plain)
            settingsRow("Notifications", "bell.fill")
            settingsRow("Payment preferences", "creditcard.fill")
            settingsRow("Address book", "person.crop.rectangle.stack.fill")
        }
    }

    private var supportSection: some View {
        Section("Support") {
            settingsRow("Contact support", "message.fill")
            settingsRow("Share feedback", "star.bubble.fill")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                settingsRowLabel("Network", "network")
                Spacer()
                Text(configuration.chainName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RecourseColor.muted)
            }
            settingsRow("Privacy", "hand.raised.fill")
            settingsRow("Terms", "doc.text.fill")
        }
    }

    private var sessionSection: some View {
        Section {
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

    private func settingsRow(_ title: String, _ systemImage: String) -> some View {
        HStack {
            settingsRowLabel(title, systemImage)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.55))
        }
    }

    private func settingsRowLabel(_ title: String, _ systemImage: String) -> some View {
        Label {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(RecourseColor.ink)
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
    let onSave: (String, String) -> Void

    init(
        givenName: String,
        familyName: String,
        onSave: @escaping (String, String) -> Void
    ) {
        _givenName = State(initialValue: givenName)
        _familyName = State(initialValue: familyName)
        self.onSave = onSave
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
                    Text("This is how your name appears in Recourse. Your Apple account email stays unchanged.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Personal details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            givenName.trimmingCharacters(in: .whitespacesAndNewlines),
                            familyName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(givenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview("Settings") {
    NavigationStack {
        AccountFoundationView(
            configuration: .live,
            accountSession: .preview()
        )
    }
    .tint(RecourseColor.ledger)
}
