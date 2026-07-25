import SwiftUI

struct RootView: View {
    let environment: AppEnvironment
    @AppStorage("recourse.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("recourse.workspaceRole") private var storedWorkspaceRole = ""
    @AppStorage("recourse.appearance") private var appearanceRaw = "dark"

    private var workspaceDestination: WorkspaceDestination {
        WorkspaceRouting.destination(
            isRestoring: environment.accountSession.isRestoring,
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
                OnboardingFlowView(accountSession: environment.accountSession) { role in
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
        }
        // A checkout QR scanned with the Camera app arrives here: as a universal link
        // (https://<web>/pay?request=...) or via the recourse:// scheme from the web
        // fallback page. Both decode to the same request the in-app scanner produces.
        .onOpenURL { url in
            openIncomingCheckout(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL {
                openIncomingCheckout(url)
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

    private func openIncomingCheckout(_ url: URL) {
        guard let request = try? PaymentRequestDecoder(configuration: environment.configuration)
            .decode(scanned: url.absoluteString) else { return }
        // Land on the review screen directly; whatever was mid-navigation is stale next
        // to a checkout the user just pointed their camera at.
        environment.router.reset()
        environment.router.push(.checkout(request))
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .checkout(let request):
            CheckoutReviewView(request: request, environment: environment)
        case .payment(let paymentID):
            if let payment = environment.paymentStore.payment(id: paymentID) {
                PaymentDetailView(payment: payment, router: environment.router)
            } else {
                missingPayment(paymentID)
            }
        case .dispute(let paymentID):
            if let payment = environment.paymentStore.payment(id: paymentID) {
                DisputeFilingView(payment: payment, environment: environment)
            } else {
                missingPayment(paymentID)
            }
        case .verdict(let paymentID):
            if let payment = environment.paymentStore.payment(id: paymentID) {
                VerdictDetailView(payment: payment)
            } else {
                missingPayment(paymentID)
            }
        case .send:
            SendMoneyView(environment: environment)
        case .earn:
            EarnView(environment: environment)
        case .account:
            AccountFoundationView(
                configuration: environment.configuration,
                accountSession: environment.accountSession,
                signer: environment.buyerSigner
            )
        case .support:
            SupportView()
        }
    }

    private func missingPayment(_ paymentID: UInt64) -> some View {
        ContentUnavailableView(
            "Payment not indexed yet",
            systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
            description: Text("Payment #\(paymentID) is not available from the live Arc indexer.")
        )
        .task {
            await environment.paymentStore.refreshBuyer()
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
