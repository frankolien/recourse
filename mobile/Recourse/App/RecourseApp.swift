import SwiftUI

@main
struct RecourseApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .tint(RecourseColor.ledger)
        }
    }
}
