import SwiftUI

struct RootView: View {
    let environment: AppEnvironment
    @AppStorage("recourse.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("recourse.workspaceRole") private var storedWorkspaceRole = ""

    var body: some View {
        @Bindable var router = environment.router

        Group {
            switch WorkspaceRouting.destination(
                isRestoring: environment.accountSession.isRestoring,
                isAuthenticated: environment.accountSession.isAuthenticated,
                hasCompletedOnboarding: hasCompletedOnboarding,
                storedRole: storedWorkspaceRole
            ) {
            case .restoring:
                ProgressView()
                    .tint(RecourseColor.ledger)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    accountLabel: environment.accountSession.account?.accountLabel ?? "Merchant account",
                    dashboardURL: environment.configuration.merchantWebURL,
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
                OnboardingFlowView(accountSession: environment.accountSession) { role in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        storedWorkspaceRole = role.rawValue
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            }
        }
        .background(RecourseColor.canvas)
        .task {
            await environment.accountSession.restore()
        }
    }

    private func resetOnboarding() {
        hasCompletedOnboarding = false
        storedWorkspaceRole = ""
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .checkout(let request):
            CheckoutReviewView(request: request, environment: environment)
        case .payment(let paymentID):
            PaymentDetailView(
                payment: environment.paymentStore.payment(id: paymentID) ?? DemoCatalog.payment(id: paymentID),
                router: environment.router
            )
        case .dispute(let paymentID):
            DisputeFilingView(
                payment: environment.paymentStore.payment(id: paymentID) ?? DemoCatalog.payment(id: paymentID),
                environment: environment
            )
        case .verdict(let paymentID):
            VerdictDetailView(
                payment: environment.paymentStore.payment(id: paymentID) ?? DemoCatalog.payment(id: paymentID)
            )
        case .account:
            AccountFoundationView(
                configuration: environment.configuration,
                accountSession: environment.accountSession
            )
        case .support:
            SupportView()
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
