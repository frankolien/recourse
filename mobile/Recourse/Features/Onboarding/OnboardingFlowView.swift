import SwiftUI

private enum OnboardingStage: Int {
    case welcome
    case signupStory
    case authentication
    case role
    case wallet
    case ready
}

struct OnboardingFlowView: View {
    let accountSession: AccountSession
    let onComplete: (OnboardingRole) -> Void
    private let buyerSigner: any BuyerSigner
    @State private var stage: OnboardingStage = .welcome
    @State private var authenticationMode: OnboardingAuthenticationMode = .signUp
    @State private var authenticationBackTarget: OnboardingStage = .welcome
    @State private var selectedRole: OnboardingRole = .buyer
    @State private var walletAddress: EthereumAddress?

    init(
        accountSession: AccountSession,
        buyerSigner: any BuyerSigner = TestnetLocalSigner(),
        onComplete: @escaping (OnboardingRole) -> Void
    ) {
        self.accountSession = accountSession
        self.buyerSigner = buyerSigner
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            RecourseColor.canvas.ignoresSafeArea()

            Group {
                switch stage {
                case .welcome:
                    OnboardingWelcomeView(
                        onGetStarted: { advance(to: .signupStory) },
                        onSignIn: { openAuthentication(mode: .signIn, backTo: .welcome) }
                    )
                case .signupStory:
                    OnboardingSignupStoryView(
                        onBack: { advance(to: .welcome) },
                        onCreateAccount: { openAuthentication(mode: .signUp, backTo: .signupStory) },
                        onSignIn: { openAuthentication(mode: .signIn, backTo: .signupStory) }
                    )
                case .authentication:
                    OnboardingSignInView(
                        mode: authenticationMode,
                        accountSession: accountSession,
                        onBack: { advance(to: authenticationBackTarget) },
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
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
            )
        }
        .onAppear {
            guard accountSession.isAuthenticated, stage == .welcome else { return }
            stage = .role
        }
    }

    private func advance(to newStage: OnboardingStage) {
        withAnimation(.spring(response: 0.48, dampingFraction: 0.9)) {
            stage = newStage
        }
    }

    private func openAuthentication(mode: OnboardingAuthenticationMode, backTo target: OnboardingStage) {
        authenticationMode = mode
        authenticationBackTarget = target
        advance(to: .authentication)
    }
}
