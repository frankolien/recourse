import SwiftUI

private enum AppTab: Hashable {
    case home
    case scan
    case receipts
}

struct AppShellView: View {
    let environment: AppEnvironment
    @State private var selection: AppTab = .home
    @State private var showsScanner = false

    var body: some View {
        TabView(selection: $selection) {
            HomeView(environment: environment)
                .tag(AppTab.home)
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            Color.clear
                .tag(AppTab.scan)
                .tabItem {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                }

            ReceiptsFoundationView()
                .tag(AppTab.receipts)
                .tabItem {
                    Label("Receipts", systemImage: "doc.text")
                }
        }
        .onChange(of: selection) { _, newValue in
            guard newValue == .scan else { return }
            selection = .home
            showsScanner = true
        }
        .fullScreenCover(isPresented: $showsScanner) {
            ScannerFoundationView()
        }
    }
}
