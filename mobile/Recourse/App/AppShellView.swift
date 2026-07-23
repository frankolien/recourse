import SwiftUI

private enum AppTab: Hashable, CaseIterable {
    case home
    case scan
    case receipts

    var label: String {
        switch self {
        case .home: "Home"
        case .scan: "Scan"
        case .receipts: "Receipts"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .scan: "qrcode.viewfinder"
        case .receipts: "wallet.bifold.fill"
        }
    }
}

struct AppShellView: View {
    let environment: AppEnvironment
    @State private var selection: AppTab = .home
    @State private var lastContentTab: AppTab = .home
    @State private var showsScanner = false
    @State private var keepsTabBarExpanded = false

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            nativeTabView
                .tabBarMinimizeBehavior(keepsTabBarExpanded ? .never : .onScrollDown)
        } else {
            nativeTabView
        }
    }

    private var nativeTabView: some View {
        TabView(selection: $selection) {
            HomeView(
                environment: environment,
                onScrollTowardTopChanged: updateTabBarExpansion,
                onScanRequested: { showsScanner = true }
            )
                .tag(AppTab.home)
                .tabItem {
                    Label(AppTab.home.label, systemImage: AppTab.home.icon)
                }

            Color.clear
                .tag(AppTab.scan)
                .tabItem {
                    Label(AppTab.scan.label, systemImage: AppTab.scan.icon)
                }

            ReceiptsFoundationView(
                environment: environment,
                onScrollTowardTopChanged: updateTabBarExpansion
            )
                .tag(AppTab.receipts)
                .tabItem {
                    Label(AppTab.receipts.label, systemImage: AppTab.receipts.icon)
                }
        }
        .tint(RecourseColor.ledgerDeep)
        .onChange(of: selection) { _, newValue in
            if newValue == .scan {
                selection = lastContentTab
                showsScanner = true
            } else {
                lastContentTab = newValue
            }
        }
        .fullScreenCover(isPresented: $showsScanner) {
            ScannerFoundationView(configuration: environment.configuration) { request in
                showsScanner = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    environment.router.push(.checkout(request))
                }
            }
        }
    }

    private func updateTabBarExpansion(_ isScrollingTowardTop: Bool) {
        guard keepsTabBarExpanded != isScrollingTowardTop else { return }
        withAnimation(.snappy(duration: 0.24)) {
            keepsTabBarExpanded = isScrollingTowardTop
        }
    }
}

struct MerchantWorkspaceView: View {
    let accountLabel: String
    let dashboardURL: URL
    let onUseBuyerApp: () -> Void
    let onSignOut: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                Image(systemName: "storefront.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
                    .frame(width: 68, height: 68)
                    .background(RecourseColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(alignment: .leading, spacing: 10) {
                    Text("MERCHANT WORKSPACE").recourseEyebrow()
                    Text("Run protected payments from the web.")
                        .font(RecourseTypography.display(size: 38))
                        .foregroundStyle(RecourseColor.ink)
                    Text("Signed in as \(accountLabel). Policies, settlements, disputes, and developer tools stay in the full Recourse dashboard.")
                        .font(.system(size: 15))
                        .foregroundStyle(RecourseColor.muted)
                        .lineSpacing(3)
                }
                Button("Open merchant dashboard") { openURL(dashboardURL) }
                    .buttonStyle(RecoursePrimaryButtonStyle())
                Button("Use the buyer app instead", action: onUseBuyerApp)
                    .buttonStyle(RecourseSecondaryButtonStyle())
                Spacer()
            }
            .padding(.horizontal, 24)
            .background(RecourseColor.canvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out", action: onSignOut)
                }
            }
        }
    }
}

#Preview("Buyer app · Liquid Glass") {
    NavigationStack {
        AppShellView(environment: .preview())
    }
    .tint(RecourseColor.ledger)
}

#Preview("Merchant handoff") {
    MerchantWorkspaceView(
        accountLabel: "frank@recourse.app",
        dashboardURL: AppConfiguration.live.merchantWebURL,
        onUseBuyerApp: {},
        onSignOut: {}
    )
    .tint(RecourseColor.ledger)
}
