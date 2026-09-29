import SwiftUI

@main
struct RecourseApp: App {
    @UIApplicationDelegateAdaptor(PushBridge.self) private var pushBridge
    @State private var environment = AppEnvironment.live()
    @State private var network = NetworkSelection.shared

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .tint(RecourseColor.ledger)
                // Changing chain rebuilds everything rather than asking each store to
                // forget. Every store captured its configuration when it was built and
                // holds that chain's figures in memory, so a switch without this shows
                // one chain's balance while talking to another, which on a money app is
                // the worst thing the screen can do. Rebuilding is also the only
                // version that cannot be half done: there is no store to forget to
                // reset, because none of the old ones survive.
                .onChange(of: network.current.chainID) { _, _ in
                    environment = AppEnvironment.live()
                }
                .id(network.current.chainID)
        }
    }
}

#if DEBUG
#Preview("First launch") {
    OnboardingFlowView(accountSession: .preview(), onComplete: { _ in })
}
#endif
