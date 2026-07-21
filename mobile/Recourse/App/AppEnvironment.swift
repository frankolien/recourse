import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let configuration: AppConfiguration
    let router: AppRouter

    init(configuration: AppConfiguration, router: AppRouter = AppRouter()) {
        self.configuration = configuration
        self.router = router
    }

    static func live() -> AppEnvironment {
        AppEnvironment(configuration: .live)
    }
}
