import SwiftUI

struct AccountFoundationView: View {
    let configuration: AppConfiguration
    let accountSession: AccountSession
    @AppStorage("recourse.hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("recourse.workspaceRole") private var storedWorkspaceRole = OnboardingRole.buyer.rawValue

    private var accountName: String { accountSession.account?.accountLabel ?? "Frank Olien" }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                profile
                networkCard
                settingsCard
                securityCard
                Button("Replay onboarding") {
                    hasCompletedOnboarding = false
                    storedWorkspaceRole = ""
                }
                .buttonStyle(RecourseSecondaryButtonStyle())
                Button("Sign out", role: .destructive) {
                    Task {
                        await accountSession.signOut()
                        hasCompletedOnboarding = false
                        storedWorkspaceRole = ""
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.red)
                .padding(.vertical, 8)
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .background(RecourseColor.canvas)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var profile: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(RecourseColor.ink).frame(width: 76, height: 76)
                Text(accountName.prefix(1).uppercased())
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Circle().fill(Color.green).frame(width: 16, height: 16).overlay(Circle().stroke(RecourseColor.canvas, lineWidth: 3)).offset(x: 28, y: 28)
            }
            VStack(spacing: 4) {
                Text(accountName).font(.system(size: 23, weight: .bold)).foregroundStyle(RecourseColor.ink)
                Text("Buyer workspace · Apple sign-in").font(.system(size: 13)).foregroundStyle(RecourseColor.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT NETWORK").recourseEyebrow()
                    Text(configuration.chainName).font(.system(size: 20, weight: .bold)).foregroundStyle(RecourseColor.ink)
                }
                Spacer()
                Circle().fill(Color.green).frame(width: 10, height: 10)
            }
            HStack {
                Text("Testnet balance").foregroundStyle(RecourseColor.muted)
                Spacer()
                Text("2,480.50 USDC").fontWeight(.bold).foregroundStyle(RecourseColor.ink)
            }
            .font(.system(size: 13))
            HStack {
                Text("Wallet").foregroundStyle(RecourseColor.muted)
                Spacer()
                Text("0x8a71…d21e").font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(RecourseColor.ink)
            }
        }
        .padding(20)
        .background(RecourseColor.softGreen, in: RoundedRectangle(cornerRadius: 22))
    }

    private var settingsCard: some View {
        ProtectedCard {
            VStack(spacing: 0) {
                accountRow("Personal details", "person.crop.circle")
                Divider().padding(.leading, 42)
                accountRow("Notifications", "bell")
                Divider().padding(.leading, 42)
                accountRow("Payment preferences", "creditcard")
                Divider().padding(.leading, 42)
                accountRow("Privacy", "hand.raised")
            }
        }
    }

    private var securityCard: some View {
        ProtectedCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Protected on this iPhone", systemImage: "iphone.gen3")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Text("Your signing key stays in the Keychain. Face ID confirms protected payment actions before anything is signed.")
                    .font(.system(size: 13))
                    .foregroundStyle(RecourseColor.muted)
                    .lineSpacing(3)
                HStack {
                    Label("Device key", systemImage: "checkmark.circle.fill")
                    Spacer()
                    Text("Active")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
            }
        }
    }

    private func accountRow(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(RecourseColor.ledger).frame(width: 28)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(RecourseColor.ink)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(RecourseColor.muted)
        }
        .padding(.vertical, 14)
    }
}

#Preview("Account") {
    NavigationStack {
        AccountFoundationView(
            configuration: .live,
            accountSession: .preview()
        )
    }
    .tint(RecourseColor.ledger)
}
