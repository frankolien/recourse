import SwiftUI

struct RootView: View {
    let environment: AppEnvironment
    @AppStorage("recourse.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("recourse.workspaceRole") private var storedWorkspaceRole = ""
    @AppStorage("recourse.appearance") private var appearanceRaw = "dark"
    // Session restore is local-only and near-instant; the hold keeps the splash
    // up long enough for its entrance animation to land instead of blinking.
    @State private var isHoldingSplash = true

    private var workspaceDestination: WorkspaceDestination {
        WorkspaceRouting.destination(
            isRestoring: environment.accountSession.isRestoring || isHoldingSplash,
            isAuthenticated: environment.accountSession.isAuthenticated,
            hasCompletedOnboarding: hasCompletedOnboarding,
            storedRole: storedWorkspaceRole
        )
    }

    var body: some View {
        @Bindable var router = environment.router

        Group {
            switch workspaceDestination {
            case .restoring:
                SplashView()
                    .transition(.opacity)
            case .buyerApp:
                NavigationStack(path: $router.path) {
                    AppShellView(environment: environment)
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                        }
                }
                .transition(.opacity)
            case .merchantWeb:
                MerchantWorkspaceView(
                    environment: environment,
                    accountLabel: environment.accountSession.account?.accountLabel ?? "Merchant account",
                    onUseBuyerApp: {
                        storedWorkspaceRole = OnboardingRole.buyer.rawValue
                    },
                    onSignOut: {
                        Task {
                            await environment.accountSession.signOut()
                            resetOnboarding()
                        }
                    }
                )
                .transition(.opacity)
            case .onboarding:
                OnboardingFlowView(
                    accountSession: environment.accountSession,
                    smartAccounts: environment.smartAccounts,
                    environment: environment
                ) { role in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        storedWorkspaceRole = role.rawValue
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            }
        }
        .recourseKeyboardDismissal()
        // The app interior follows the user's appearance pick (Settings), dark
        // by default; onboarding always keeps its white-and-green world. The
        // scheme also flips system chrome (sheets, keyboards) per branch.
        .background(workspaceDestination == .buyerApp ? RecourseColor.night : RecourseColor.canvas)
        .preferredColorScheme(inAppColorScheme)
        .task {
            await environment.accountSession.restore()
            await environment.smartAccounts.load()
            // A tapped alert opens its proposal, including one tapped before launch.
            PushBridge.shared.onRoute = { route in environment.router.push(route) }
            PushBridge.shared.onHistory = { environment.router.showHistory() }
        }
        .task {
            // Glyph beat, wordmark sweep, then a moment to read it.
            try? await Task.sleep(for: .seconds(2.3))
            withAnimation(.easeInOut(duration: 0.45)) {
                isHoldingSplash = false
            }
        }
    }

    private var inAppColorScheme: ColorScheme {
        guard workspaceDestination == .buyerApp else { return .light }
        return appearanceRaw == "light" ? .light : .dark
    }

    private func resetOnboarding() {
        hasCompletedOnboarding = false
        storedWorkspaceRole = ""
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .send:
            SendMoneyView(environment: environment)
        case .convert:
            // Quoting is a read, so this needs no signer state from the
            // environment. The default signer resolves the same scoped keystore.
            ConvertView(reader: try? ArcContractGateway.live())
        case .cheques:
            ChequesView(environment: environment)
        case .writeCheque:
            WriteChequeView(environment: environment)
        case .invoices:
            InvoicesView(environment: environment)
        case .newInvoice:
            NewInvoiceView(environment: environment)
        case .earn:
            EarnView(environment: environment)
        case .account:
            AccountFoundationView(environment: environment)
        case .support:
            SupportView()
        case .keys:
            KeysView(environment: environment)
        case .team:
            TeamView(environment: environment)
        case .teamAccount(let address):
            TeamAccountView(environment: environment, address: address)
        case .teamProposal(let account, let txHash):
            TeamProposalView(environment: environment, account: account, txHash: txHash)
        }
    }

}

enum WorkspaceDestination: Equatable {
    case restoring
    case onboarding
    case buyerApp
    case merchantWeb
}

enum WorkspaceRouting {
    static func destination(
        isRestoring: Bool,
        isAuthenticated: Bool,
        hasCompletedOnboarding: Bool,
        storedRole: String
    ) -> WorkspaceDestination {
        if isRestoring {
            return .restoring
        }
        guard isAuthenticated,
              hasCompletedOnboarding,
              let role = OnboardingRole(rawValue: storedRole) else {
            return .onboarding
        }
        return role == .buyer ? .buyerApp : .merchantWeb
    }
}
