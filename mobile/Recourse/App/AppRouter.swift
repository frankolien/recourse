import Observation

enum AppRoute: Hashable {
    case checkout(PaymentRequest)
    case payment(UInt64)
    case dispute(UInt64)
    case verdict(UInt64)
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
