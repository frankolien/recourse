import Observation

enum AppRoute: Hashable {
    case send
    case convert
    case cheques
    case writeCheque
    case invoices
    case newInvoice
    case earn
    case account
    case support
    case keys
    case team
    case teamAccount(String)
    case teamProposal(account: String, txHash: String)
}

@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []
    /// Bumped when something outside the tab bar wants the History tab shown, such as
    /// a tapped "Received" alert. The shell watches it and switches tabs.
    var historyRequests = 0

    func showHistory() {
        path.removeAll()
        historyRequests += 1
    }

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func reset() {
        path.removeAll()
    }
}
