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
}

@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func reset() {
        path.removeAll()
    }
}
