import SwiftUI

struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        @Bindable var router = environment.router

        NavigationStack(path: $router.path) {
            AppShellView(environment: environment)
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .background(RecourseColor.canvas)
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .checkout(let request):
            PlaceholderDetailView(
                eyebrow: "PROTECTED CHECKOUT",
                title: request.amount.formatted,
                message: "Policy #\(request.policyID) is ready for onchain review."
            )
        case .payment(let paymentID):
            PlaceholderDetailView(
                eyebrow: "RECEIPT",
                title: "Payment #\(paymentID)",
                message: "Chain-authoritative payment detail lands in M4.3."
            )
        case .dispute(let paymentID):
            PlaceholderDetailView(
                eyebrow: "FILE A DISPUTE",
                title: "Payment #\(paymentID)",
                message: "Camera evidence and filing land in M4.4."
            )
        case .verdict(let paymentID):
            PlaceholderDetailView(
                eyebrow: "VERDICT",
                title: "Payment #\(paymentID)",
                message: "The app will read previewVerdict from Arc."
            )
        case .account:
            AccountFoundationView(configuration: environment.configuration)
        case .support:
            PlaceholderDetailView(
                eyebrow: "SUPPORT",
                title: "We are here to help.",
                message: "Support channels will be connected before TestFlight."
            )
        }
    }
}
