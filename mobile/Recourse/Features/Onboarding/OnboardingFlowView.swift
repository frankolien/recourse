import SwiftUI

private enum OnboardingStage: Int {
    case welcome
    case authentication
    case role
    case wallet
    case ready
}

struct OnboardingFlowView: View {
    let accountSession: AccountSession
    let onComplete: (OnboardingRole) -> Void
    private let buyerSigner: any BuyerSigner
    private let smartAccounts: SmartAccountStore?
    @State private var stage: OnboardingStage = .welcome
    @State private var selectedRole: OnboardingRole = .buyer
    @State private var walletAddress: EthereumAddress?

    init(
        accountSession: AccountSession,
        buyerSigner: any BuyerSigner = TestnetLocalSigner(),
        smartAccounts: SmartAccountStore? = nil,
        onComplete: @escaping (OnboardingRole) -> Void
    ) {
        self.accountSession = accountSession
        self.buyerSigner = buyerSigner
        self.smartAccounts = smartAccounts
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            RecourseColor.canvas.ignoresSafeArea()

            Group {
                switch stage {
                case .welcome:
                    OnboardingWelcomeView(
                        onGetStarted: { advance(to: .authentication) }
                    )
                case .authentication:
                    OnboardingAuthenticationView(
                        accountSession: accountSession,
                        onBack: { advance(to: .welcome) },
                        onAuthenticated: { advance(to: .role) }
                    )
                case .role:
                    OnboardingSetupView(
                        accountLabel: accountSession.account?.accountLabel ?? "APPLE ACCOUNT",
                        onBack: { advance(to: .authentication) },
                        onContinue: { role in
                            selectedRole = role
                            advance(to: role == .buyer ? .wallet : .ready)
                        }
                    )
                case .wallet:
                    OnboardingWalletSetupView(
                        signer: buyerSigner,
                        smartAccounts: smartAccounts,
                        onBack: { advance(to: .role) },
                        onContinue: { address in
                            walletAddress = address
                            advance(to: .ready)
                        }
                    )
                case .ready:
                    OnboardingReadyView(
                        role: selectedRole,
                        walletAddress: walletAddress,
                        onComplete: { onComplete(selectedRole) }
                    )
                }
            }
            .id(stage)
        }
        .onAppear {
            guard accountSession.isAuthenticated, stage == .welcome else { return }
            stage = .role
        }
    }

    // Onboarding steps swap outright. A slide between them animated every tap,
    // including Back, which read as the flow performing rather than responding.
    private func advance(to newStage: OnboardingStage) {
        stage = newStage
    }

}
