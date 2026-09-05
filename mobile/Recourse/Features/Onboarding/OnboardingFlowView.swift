import SwiftUI

private enum OnboardingStage: Int {
    case welcome
    case authentication
    case wallet
    case ready
}

struct OnboardingFlowView: View {
    let accountSession: AccountSession
    let onComplete: (OnboardingRole) -> Void
    private let buyerSigner: any BuyerSigner
    private let smartAccounts: SmartAccountStore?
    @State private var stage: OnboardingStage = .welcome
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
                        // Everyone is a person with money now. The old question of
                        // buyer or merchant is gone with the checkout it served.
                        onAuthenticated: { advance(to: .wallet) }
                    )
                case .wallet:
                    OnboardingWalletSetupView(
                        signer: buyerSigner,
                        smartAccounts: smartAccounts,
                        onBack: { advance(to: .authentication) },
                        onContinue: { address in
                            walletAddress = address
                            advance(to: .ready)
                        }
                    )
                case .ready:
                    OnboardingReadyView(
                        role: .buyer,
                        walletAddress: walletAddress,
                        onComplete: { onComplete(.buyer) }
                    )
                }
            }
            .id(stage)
        }
        .onAppear {
            guard accountSession.isAuthenticated, stage == .welcome else { return }
            stage = .wallet
        }
    }

    // Onboarding steps swap outright. A slide between them animated every tap,
    // including Back, which read as the flow performing rather than responding.
    private func advance(to newStage: OnboardingStage) {
        stage = newStage
    }

}
