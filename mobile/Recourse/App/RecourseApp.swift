import SwiftUI

@main
struct RecourseApp: App {
    @UIApplicationDelegateAdaptor(PushBridge.self) private var pushBridge
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .tint(RecourseColor.ledger)
        }
    }
}

#if DEBUG
#Preview("First launch") {
    OnboardingFlowView(accountSession: .preview(), onComplete: { _ in })
}
#endif
