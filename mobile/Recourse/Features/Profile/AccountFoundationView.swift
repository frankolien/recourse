import SwiftUI

struct AccountFoundationView: View {
    let configuration: AppConfiguration
    let accountSession: AccountSession
    @AppStorage("recourse.hasCompletedOnboarding") private var hasCompletedOnboarding = true

    var body: some View {
        List {
            if let account = accountSession.account {
                Section("Account") {
                    LabeledContent("Signed in with", value: "Apple")
                    LabeledContent("Account", value: account.accountLabel)
                }
            }

            Section("Network") {
                LabeledContent("Chain", value: configuration.chainName)
                LabeledContent("Chain ID", value: String(configuration.chainID))
            }

            Section("Deployment") {
                LabeledContent("Escrow", value: configuration.escrowAddress.shortened)
                LabeledContent("USDC", value: configuration.usdcAddress.shortened)
            }

            Section {
                Text("A testnet account will be created on-device in the signing slice. No production funds are supported.")
                    .font(.footnote)
                    .foregroundStyle(RecourseColor.muted)
            }

            Section {
                Button("Replay onboarding") {
                    hasCompletedOnboarding = false
                }

                Button("Sign out", role: .destructive) {
                    Task {
                        await accountSession.signOut()
                        hasCompletedOnboarding = false
                    }
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}
