import SwiftUI
import CoreImage.CIFilterBuiltins
import PhotosUI
import UIKit

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
    let environment: AppEnvironment
    let accountLabel: String
    let onUseBuyerApp: () -> Void
    let onSignOut: () -> Void

    @State private var selectedPage = MerchantPage.overview
    @State private var selectedPolicyID: UInt64?
    @State private var amount = ""
    @State private var orderReference = ""
    @State private var itemName = ""
    @State private var itemDescription = ""
    @State private var selectedProductPhoto: PhotosPickerItem?
    @State private var productImageData: Data?
    @State private var isLoadingProductPhoto = false
    @State private var qrCardSaved = false
    @State private var isCreatingCheckout = false
    @State private var checkoutStatusMessage: String?
    @State private var checkoutPresentation: CheckoutPresentation?
    @State private var checkoutErrorMessage: String?
    @State private var hasCopiedWalletAddress = false
    @State private var isPublishingPolicy = false
    @State private var policyStatusMessage: String?

    private let merchantAccent = Color(red: 15 / 255, green: 118 / 255, blue: 110 / 255)
    private let merchantCanvas = Color(red: 247 / 255, green: 248 / 255, blue: 246 / 255)
    private let merchantCard = Color(red: 252 / 255, green: 253 / 255, blue: 252 / 255)
    private let merchantDark = Color(red: 10 / 255, green: 35 / 255, blue: 35 / 255)

    private struct CheckoutPresentation: Identifiable {
        let id = UUID()
        let request: PaymentRequest
        let manifest: OrderManifest
        let encodedRequest: String
        let image: UIImage
        // Pre-rendered branded card (QR + order summary) so Save and Share hand the
        // buyer one self-contained image; the app can pay from an imported screenshot.
        let shareCard: UIImage
    }

    private enum MerchantPage: String, CaseIterable {
        case overview = "Home"
        case checkout = "Checkout"
        case payments = "Payments"

        var icon: String {
            switch self {
            case .overview: "chart.bar.fill"
            case .checkout: "qrcode"
            case .payments: "list.bullet.rectangle"
            }
        }
    }

    private var merchantAddress: EthereumAddress? {
        environment.paymentStore.walletAddress
    }

    private var merchantPolicies: [PolicyRecord] {
        guard let merchantAddress else { return [] }
        return environment.paymentStore.policies.filter {
            $0.merchant.value.caseInsensitiveCompare(merchantAddress.value) == .orderedSame
        }
    }

    private var receivedTotal: USDCAmount {
        USDCAmount(
            baseUnits: environment.paymentStore.merchantPayments.reduce(0) {
                $0 + $1.amount.baseUnits
            }
        )
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedPage) {
                merchantOverviewPage
                    .tag(MerchantPage.overview)
                    .tabItem {
                        Label(MerchantPage.overview.rawValue, systemImage: MerchantPage.overview.icon)
                    }

                merchantCheckoutPage
                    .tag(MerchantPage.checkout)
                    .tabItem {
                        Label(MerchantPage.checkout.rawValue, systemImage: MerchantPage.checkout.icon)
                    }

                merchantPaymentsPage
                    .tag(MerchantPage.payments)
                    .tabItem {
                        Label(MerchantPage.payments.rawValue, systemImage: MerchantPage.payments.icon)
                    }
            }
            .tint(merchantAccent)
            .navigationTitle(selectedPage.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(merchantCanvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Switch to buyer", action: onUseBuyerApp)
                        Button("Sign out", role: .destructive, action: onSignOut)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(merchantDark)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Circle()
                        .fill(merchantAccent)
                        .frame(width: 10, height: 10)
                        .accessibilityLabel("Arc Testnet")
                }
            }
        }
        .background(merchantCanvas.ignoresSafeArea())
        .task {
            while !Task.isCancelled {
                await environment.paymentStore.refreshMerchant()
                selectedPolicyID = selectedPolicyID ?? merchantPolicies.first?.id
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .onChange(of: merchantPolicies) { _, policies in
            if selectedPolicyID == nil {
                selectedPolicyID = policies.first?.id
            }
        }
        .sheet(item: $checkoutPresentation, onDismiss: resetCheckoutForm) { presentation in
            checkoutQRSheet(presentation)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var merchantOverviewPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                merchantOverview
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 120)
        }
        .refreshable {
            await environment.paymentStore.refreshMerchant()
        }
        .background(merchantCanvas)
    }

    private var merchantCheckoutPage: some View {
        ScrollView {
            checkoutBuilder
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(merchantCanvas)
    }

    private var merchantPaymentsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PAYMENT LEDGER")
                            .recourseEyebrow()
                        Text("Every protected sale.")
                            .font(.system(size: 28, weight: .bold))
                    }
                    Spacer()
                    Text("\(environment.paymentStore.merchantPayments.count)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RecourseColor.muted)
                }
                paymentLedger
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .refreshable {
            await environment.paymentStore.refreshMerchant()
        }
        .background(merchantCanvas)
    }

    private var merchantOverview: some View {
        VStack(alignment: .leading, spacing: 17) {
            salesPulse
            walletBalanceStrip

            Button {
                selectedPage = .checkout
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Take a protected payment")
                            .font(.system(size: 16, weight: .bold))
                        Text("Amount → policy → QR")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.76))
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 60)
                .background(merchantAccent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: merchantAccent.opacity(0.16), radius: 12, y: 6)
            }
            .buttonStyle(.plain)

            HStack {
                Text("Latest activity")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(merchantDark)
                Spacer()
                Button("See all") {
                    selectedPage = .payments
                }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(merchantAccent)
            }

            if environment.paymentStore.merchantPayments.isEmpty {
                merchantEmptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(environment.paymentStore.merchantPayments.prefix(4)) {
                        merchantPaymentRow($0)
                        if $0.id != environment.paymentStore.merchantPayments.prefix(4).last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    private var salesPulse: some View {
        ZStack(alignment: .topTrailing) {
            // A whisper of brand color on an otherwise neutral dark card; green is the
            // accent here, not the wallpaper.
            Circle()
                .fill(merchantAccent.opacity(0.1))
                .frame(width: 170, height: 170)
                .blur(radius: 46)
                .offset(x: 54, y: -62)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Protected sales", systemImage: "shield.checkered")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text("ARC TESTNET")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.35)
                        .foregroundStyle(.white.opacity(0.68))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(currency(receivedTotal))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.72)
                    Text("\(environment.paymentStore.merchantPayments.count) payments received")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                }
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Settlement activity is indexed live")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.84))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(RecourseColor.inkSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: RecourseColor.ink.opacity(0.15), radius: 18, y: 10)
    }

    private var walletBalanceStrip: some View {
        HStack(spacing: 11) {
            Image(systemName: "wallet.bifold")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RecourseColor.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text("Wallet balance")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RecourseColor.muted)
                Text(merchantAddress?.shortened ?? "Preparing wallet…")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(RecourseColor.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(environment.paymentStore.balance.map(currency) ?? "Checking…")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(merchantDark)
                Text("USDC")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(RecourseColor.muted)
            }
            Button(action: copyMerchantWalletAddress) {
                Image(systemName: hasCopiedWalletAddress ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hasCopiedWalletAddress ? merchantAccent : RecourseColor.ink)
                    .frame(width: 32, height: 32)
                    .background(RecourseColor.clay, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(merchantAddress == nil)
            .accessibilityLabel(hasCopiedWalletAddress ? "Wallet address copied" : "Copy wallet address")
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(merchantCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.045), lineWidth: 1)
        }
    }

    private func copyMerchantWalletAddress() {
        guard let merchantAddress else { return }
        UIPasteboard.general.string = merchantAddress.value
        withAnimation(.snappy(duration: 0.2)) {
            hasCopiedWalletAddress = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            hasCopiedWalletAddress = false
        }
    }

    private var checkoutBuilder: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NEW CHECKOUT")
                    .recourseEyebrow()
                Text("What should the buyer pay?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Text("They will review the protection policy before approving it.")
                    .font(.system(size: 13))
                    .foregroundStyle(RecourseColor.muted)
            }

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    TextField("0.00", text: $amount)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 52, weight: .medium, design: .rounded))
                        .minimumScaleFactor(0.65)
                    .keyboardType(.decimalPad)
                    Text("USDC")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(RecourseColor.muted)
                }
                .frame(maxWidth: .infinity)
                Text("Funds settle to \(merchantAddress?.shortened ?? "your merchant wallet")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RecourseColor.muted)
            }
            .padding(.vertical, 20)

            VStack(alignment: .leading, spacing: 14) {
                Text("Checkout details")
                    .font(.system(size: 16, weight: .bold))

                TextField("Item or service name", text: $itemName)
                    .padding(.horizontal, 15)
                    .frame(height: 52)
                    .background(RecourseColor.surface, in: RoundedRectangle(cornerRadius: 16))

                TextField("What does the buyer receive?", text: $itemDescription, axis: .vertical)
                    .lineLimit(2 ... 4)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 15)
                    .background(RecourseColor.surface, in: RoundedRectangle(cornerRadius: 16))

                productImagePicker

                TextField("Order reference", text: $orderReference)
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, 15)
                    .frame(height: 52)
                    .background(RecourseColor.surface, in: RoundedRectangle(cornerRadius: 16))

                if merchantPolicies.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "A starter policy protects non-delivery and damaged-item claims.",
                            systemImage: "shield.checkered"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RecourseColor.muted)

                        Button {
                            Task { await publishStarterPolicy() }
                        } label: {
                            HStack {
                                if isPublishingPolicy {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "shield.badge.plus")
                                }
                                Text(isPublishingPolicy ? "Publishing on Arc…" : "Publish starter policy")
                                Spacer()
                                if !isPublishingPolicy {
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 15)
                            .frame(height: 48)
                            .background(
                                merchantDark,
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isPublishingPolicy)

                        if let policyStatusMessage {
                            Text(policyStatusMessage)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(RecourseColor.muted)
                        }
                    }
                } else {
                    Menu {
                        Picker("Protection policy", selection: $selectedPolicyID) {
                            ForEach(merchantPolicies, id: \.id) { policy in
                                Text("Policy #\(policy.id)").tag(Optional(policy.id))
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "shield.checkered")
                                .foregroundStyle(RecourseColor.ledger)
                            Text(selectedPolicyID.map { "Policy #\($0)" } ?? "Choose protection policy")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(RecourseColor.ink)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(RecourseColor.muted)
                        }
                        .padding(.horizontal, 15)
                        .frame(height: 52)
                        .background(RecourseColor.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                }

                Button {
                    Task { await generateCheckout() }
                } label: {
                    HStack(spacing: 9) {
                        if isCreatingCheckout {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "qrcode")
                        }
                        Text(isCreatingCheckout
                            ? (checkoutStatusMessage ?? "Creating order…")
                            : "Create payment QR")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        merchantAccent,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(merchantPolicies.isEmpty || isPublishingPolicy || isCreatingCheckout)
                .opacity(merchantPolicies.isEmpty ? 0.45 : 1)

                if let checkoutErrorMessage {
                    Label(checkoutErrorMessage, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .background(RecourseColor.clay, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(RecourseColor.line, lineWidth: 1)
            }

        }
    }

    private var paymentLedger: some View {
        Group {
            if environment.paymentStore.merchantPayments.isEmpty {
                merchantEmptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(environment.paymentStore.merchantPayments.enumerated()), id: \.element.id) {
                        index,
                        payment in
                        merchantPaymentRow(payment)
                        if index < environment.paymentStore.merchantPayments.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    private var merchantEmptyState: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: "qrcode")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(merchantAccent)
                .frame(width: 40, height: 40)
                .background(merchantAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
            Text("Ready for the first payment")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(merchantDark)
            Text("Create a checkout QR after publishing a policy for this wallet.")
                .font(.system(size: 13))
                .foregroundStyle(RecourseColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(merchantCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.045), lineWidth: 1)
        }
        .shadow(color: merchantDark.opacity(0.06), radius: 14, y: 7)
    }

    private func checkoutQRSheet(_ presentation: CheckoutPresentation) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Checkout published")
                    .font(.system(size: 24, weight: .bold))
                Text("Save or share this card. The buyer scans it live or imports the image.")
                    .font(.system(size: 13))
                    .foregroundStyle(RecourseColor.muted)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            Image(uiImage: presentation.shareCard)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 310)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 24, y: 12)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button {
                    UIImageWriteToSavedPhotosAlbum(presentation.shareCard, nil, nil, nil)
                    withAnimation(.snappy) { qrCardSaved = true }
                } label: {
                    Label(
                        qrCardSaved ? "Saved" : "Save image",
                        systemImage: qrCardSaved ? "checkmark" : "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(RecourseSecondaryButtonStyle())

                ShareLink(
                    item: Image(uiImage: presentation.shareCard),
                    preview: SharePreview(
                        "\(presentation.manifest.itemName) · \(presentation.request.amount.formatted)",
                        image: Image(uiImage: presentation.shareCard)
                    )
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RecoursePrimaryButtonStyle())
            }
            Text("Closing this starts a fresh checkout.")
                .font(.system(size: 11))
                .foregroundStyle(RecourseColor.muted)
        }
        .padding(24)
        .background(RecourseColor.surface)
    }

    // The exported card: brand, QR, and order summary on an always-light canvas so it
    // stays legible in any chat theme or photo grid it lands in.
    private struct CheckoutShareCard: View {
        let qr: UIImage
        let amountText: String
        let itemName: String
        let policyLine: String

        private let ledger = Color(red: 11 / 255, green: 112 / 255, blue: 84 / 255)
        private let ink = Color(red: 16 / 255, green: 24 / 255, blue: 21 / 255)

        var body: some View {
            VStack(spacing: 20) {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(ledger, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text("Recourse")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(ink)
                    Spacer()
                    Text("ARC TESTNET")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(ledger)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(ledger.opacity(0.1), in: Capsule())
                }
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 252, height: 252)
                VStack(spacing: 5) {
                    Text(amountText)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                    Text(itemName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text(policyLine)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.55))
                        .lineLimit(1)
                }
                Rectangle()
                    .fill(ink.opacity(0.08))
                    .frame(height: 1)
                Text("Protected USDC checkout. Scan it live or import this image in the Recourse app.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ink.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .padding(26)
            .frame(width: 360)
            .background(.white)
        }
    }

    @MainActor
    private func renderedShareCard(
        qr: UIImage,
        amountText: String,
        itemName: String,
        policyLine: String
    ) -> UIImage {
        let renderer = ImageRenderer(
            content: CheckoutShareCard(
                qr: qr,
                amountText: amountText,
                itemName: itemName,
                policyLine: policyLine
            )
        )
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage ?? qr
    }

    private func resetCheckoutForm() {
        amount = ""
        itemName = ""
        itemDescription = ""
        orderReference = ""
        selectedProductPhoto = nil
        productImageData = nil
        qrCardSaved = false
        checkoutErrorMessage = nil
    }

    // Publishes a protected order: optional image upload, then the manifest whose
    // keccak256 becomes the on-chain orderRef, then the v2 QR carrying that hash. The
    // buyer re-fetches the manifest by hash and verifies it before paying.
    @MainActor
    private func generateCheckout() async {
        guard !isCreatingCheckout else { return }
        checkoutErrorMessage = nil

        guard let merchantAddress else {
            checkoutErrorMessage = "The merchant wallet is still loading. Try again in a moment."
            return
        }
        guard let amount = try? USDCAmount(decimalString: amount) else {
            checkoutErrorMessage = "Enter a valid USDC amount."
            return
        }
        guard amount.baseUnits > 0 else {
            checkoutErrorMessage = "The payment amount must be greater than zero."
            return
        }
        guard let selectedPolicyID else {
            checkoutErrorMessage = "Publish a protection policy for this merchant wallet first."
            return
        }
        let name = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            checkoutErrorMessage = "Name the item or service the buyer is paying for."
            return
        }
        let details = itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !details.isEmpty else {
            checkoutErrorMessage = "Describe what the buyer receives."
            return
        }
        // A picked photo loads asynchronously (iCloud originals can take seconds), and
        // publishing before it lands would silently ship the order without its image.
        guard !isLoadingProductPhoto else {
            checkoutErrorMessage = "The product photo is still loading. Try again in a second."
            return
        }

        let trimmedReference = orderReference.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedReference = trimmedReference.isEmpty
            ? "ORDER-\(Int(Date().timeIntervalSince1970))"
            : trimmedReference
        orderReference = resolvedReference

        isCreatingCheckout = true
        defer {
            isCreatingCheckout = false
            checkoutStatusMessage = nil
        }

        do {
            let api = environment.makeOrderAPIClient()

            var imageHash: String?
            var imageContentType: String?
            if let productImageData {
                checkoutStatusMessage = "Uploading product image…"
                guard let compressed = compressedProductImage(productImageData) else {
                    checkoutErrorMessage = "The selected photo could not be read. Choose another image."
                    return
                }
                let stored = try await api.uploadImage(compressed, contentType: "image/jpeg")
                imageHash = stored.hash
                imageContentType = stored.contentType
            }

            checkoutStatusMessage = "Publishing order…"
            let manifest = OrderManifest(
                version: 1,
                chainID: environment.configuration.chainID,
                escrow: environment.configuration.escrowAddress.value,
                merchant: merchantAddress.value,
                policyID: selectedPolicyID,
                amount: String(amount.baseUnits),
                orderReference: resolvedReference,
                itemName: name,
                description: details,
                imageHash: imageHash,
                imageContentType: imageContentType,
                createdAt: Int64(Date().timeIntervalSince1970)
            )
            let (manifestBytes, orderReferenceHash) = try manifest.encodedForPublishing()
            _ = try await api.publishManifest(manifestBytes)

            let request = PaymentRequest(
                version: 2,
                chainID: environment.configuration.chainID,
                escrow: environment.configuration.escrowAddress,
                policyID: selectedPolicyID,
                merchant: merchantAddress,
                amount: amount,
                orderReference: orderReferenceHash
            )
            guard let payload = encoded(request),
                  let image = qrCode(checkoutLink(payload)) else {
                checkoutErrorMessage = "Recourse could not render this checkout QR. Try again."
                return
            }
            let encodedRequest = checkoutLink(payload)
            qrCardSaved = false
            checkoutPresentation = CheckoutPresentation(
                request: request,
                manifest: manifest,
                encodedRequest: encodedRequest,
                image: image,
                shareCard: renderedShareCard(
                    qr: image,
                    amountText: amount.formatted,
                    itemName: name,
                    policyLine: "Policy #\(selectedPolicyID) · \(resolvedReference)"
                )
            )
        } catch let error as OrderAPIError {
            switch error {
            case .rejected(let status, let message):
                checkoutErrorMessage = "The order service rejected this checkout (\(status)): \(message)"
            case .invalidResponse:
                checkoutErrorMessage = "The order service returned an unexpected response. Try again."
            }
        } catch {
            checkoutErrorMessage = "The order could not be published. Check the backend connection and try again."
        }
    }

    private var productImagePicker: some View {
        HStack(spacing: 12) {
            if let attachedImageData = productImageData,
               let preview = UIImage(data: attachedImageData) {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Product photo attached")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RecourseColor.ink)
                    Text("Buyers see it before paying")
                        .font(.system(size: 11))
                        .foregroundStyle(RecourseColor.muted)
                }
                Spacer()
                Button {
                    selectedProductPhoto = nil
                    productImageData = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(RecourseColor.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove product photo")
            } else {
                PhotosPicker(selection: $selectedProductPhoto, matching: .images) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(merchantAccent)
                        Text("Add a product photo (optional)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(RecourseColor.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(RecourseColor.muted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 60)
        .background(RecourseColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: selectedProductPhoto) { _, item in
            guard let item else { return }
            isLoadingProductPhoto = true
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data {
                        productImageData = data
                    } else {
                        checkoutErrorMessage = "The selected photo could not be loaded. Choose another image."
                        selectedProductPhoto = nil
                    }
                    isLoadingProductPhoto = false
                }
            }
        }
    }

    // Downscale and re-encode before upload: checkout photos do not need camera-native
    // resolution, and the backend caps image bodies at 5 MB.
    private func compressedProductImage(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 1200
        let largestSide = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / max(largestSide, 1))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    @MainActor
    private func publishStarterPolicy() async {
        guard !isPublishingPolicy else { return }
        isPublishingPolicy = true
        checkoutErrorMessage = nil
        policyStatusMessage = "Confirm the transaction with Face ID."
        defer { isPublishingPolicy = false }

        do {
            let gateway = try environment.makeContractGateway()
            let transactionHash = try await gateway.registerStarterPolicy()
            policyStatusMessage = "Waiting for Arc confirmation…"
            let receipt = try await gateway.waitForReceipt(transactionHash: transactionHash)
            guard receipt.outcome == .confirmed else {
                checkoutErrorMessage = "Arc reverted the policy transaction."
                policyStatusMessage = nil
                return
            }

            policyStatusMessage = "Policy confirmed. Syncing checkout…"
            for _ in 0 ..< 8 {
                await environment.paymentStore.refreshMerchant()
                if let policy = merchantPolicies.first {
                    selectedPolicyID = policy.id
                    policyStatusMessage = "Policy #\(policy.id) is live."
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
            policyStatusMessage = "Policy confirmed. Pull to refresh if it does not appear yet."
        } catch {
            policyStatusMessage = nil
            checkoutErrorMessage = "Could not publish the policy. Make sure this wallet has Arc gas and try again."
        }
    }

    private func encoded(_ request: PaymentRequest) -> String? {
        guard let data = try? JSONEncoder().encode(request) else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // The QR carries a universal link, not a bare payload, so the iPhone Camera opens
    // the app directly (or the web fallback without it). base64url is URL-safe as-is.
    private func checkoutLink(_ payload: String) -> String {
        "\(AppConfiguration.webAppURL.absoluteString)/pay?request=\(payload)"
    }

    private func qrCode(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let image = CIContext().createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private func merchantPaymentRow(_ payment: DemoPayment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: payment.state.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RecourseColor.ink)
                .frame(width: 40, height: 40)
                .background(RecourseColor.clay, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(payment.orderReference)
                    .font(.system(size: 14, weight: .semibold))
                Text(payment.state.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(RecourseColor.muted)
            }
            Spacer()
            Text(currency(payment.amount))
                .font(.system(size: 14, weight: .bold))
        }
        .padding(.vertical, 12)
    }

    private func currency(_ amount: USDCAmount) -> String {
        String(
            format: "$%.2f",
            Double(amount.baseUnits) / Double(USDCAmount.base)
        )
    }
}

#if DEBUG
#Preview("Buyer app · Liquid Glass") {
    NavigationStack {
        AppShellView(environment: .preview())
    }
    .tint(RecourseColor.ledger)
}

#Preview("Merchant handoff") {
    MerchantWorkspaceView(
        environment: .preview(),
        accountLabel: "frank@recourse.app",
        onUseBuyerApp: {},
        onSignOut: {}
    )
    .tint(RecourseColor.ledger)
}
#endif
