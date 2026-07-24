import SwiftUI

struct HomeView: View {
    let environment: AppEnvironment
    let onScrollTowardTopChanged: (Bool) -> Void
    let onScanRequested: () -> Void
    @State private var previousScrollOffset: CGFloat = 0
    @State private var hidesAttention = false

    init(
        environment: AppEnvironment,
        onScrollTowardTopChanged: @escaping (Bool) -> Void = { _ in },
        onScanRequested: @escaping () -> Void = {}
    ) {
        self.environment = environment
        self.onScrollTowardTopChanged = onScrollTowardTopChanged
        self.onScanRequested = onScanRequested
    }

    // Profile names live on the account session (persisted via the backend profile
    // endpoint), so the greeting updates the moment an edit saves, on every device.
    private var displayName: String {
        environment.accountSession.account?.displayName
            ?? environment.accountSession.account?.email?.split(separator: "@").first.map(String.init)
            ?? "there"
    }

    private var activePayments: [DemoPayment] {
        allPayments.filter { $0.state == .protected || $0.state == .underReview }
    }

    private var settledPayments: [DemoPayment] {
        allPayments.filter { $0.state == .refunded || $0.state == .released }
    }

    private var allPayments: [DemoPayment] {
        environment.paymentStore.payments
    }

    private var attentionPayment: DemoPayment? {
        allPayments.first { $0.state == .actionNeeded }
    }

    private var protectedTotal: USDCAmount {
        USDCAmount(
            baseUnits: activePayments.reduce(into: 0) { total, payment in
                total = total.addingReportingOverflow(payment.amount.baseUnits).partialValue
            }
        )
    }

    var body: some View {
        ZStack {
            homeCanvas
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    scrollPositionReader
                    protectionHero
                    paymentActions
                    attentionLead
                    protectedNow
                    receiptsAndOutcomes
                }
                .padding(.horizontal, 20)
                //.padding(.top, 20)
                .padding(.bottom, 164)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await environment.paymentStore.refreshBuyer()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            identityHeader
                .padding(.horizontal, 20)
                .frame(height: 72)
                .background(RecourseColor.surface)
        }
        .coordinateSpace(name: "recourse-home-scroll")
        .onPreferenceChange(RecourseScrollOffsetPreferenceKey.self) { newOffset in
            reportScrollDirection(newOffset)
        }
        .task {
            while !Task.isCancelled {
                await environment.paymentStore.refreshBuyer()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private var homeCanvas: some View {
        RecourseColor.surface
    }

    private var scrollPositionReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: RecourseScrollOffsetPreferenceKey.self,
                value: proxy.frame(in: .named("recourse-home-scroll")).minY
            )
        }
        .frame(height: 0)
    }

    private func reportScrollDirection(_ newOffset: CGFloat) {
        let delta = newOffset - previousScrollOffset
        guard abs(delta) > 2 else { return }
        onScrollTowardTopChanged(delta > 0)
        previousScrollOffset = newOffset
    }

    private var identityHeader: some View {
        HStack(spacing: 10) {
            Button {
                environment.router.push(.account)
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundStyle(RecourseColor.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open profile")

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                HStack(spacing: 5) {
                    Circle().fill(RecourseColor.ledger).frame(width: 7, height: 7)
                    Text("Protected on Arc Testnet")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(RecourseColor.muted)
                }
            }

            Spacer()

            Button {
                if let paymentID = settledPayments.first?.id ?? allPayments.first?.id {
                    environment.router.push(.verdict(paymentID))
                }
            } label: {
                headerAction(title: "Verify", systemImage: "checkmark.seal.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Verify a payment")

            Button {
                environment.router.push(.support)
            } label: {
                ZStack(alignment: .topTrailing) {
                    headerAction(title: "Alerts", systemImage: "bell")
                    Circle()
                        .fill(RecourseColor.ledger)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: -5, y: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notifications")
        }
    }

    private func headerAction(title: String, systemImage: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(height: 19)
            Text(title)
                .font(.system(size: 8, weight: .semibold))
        }
        .frame(width: 38)
        .foregroundStyle(RecourseColor.ink)
    }

    private var attentionLead: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(hidesAttention ? "Protection status" : "Needs your attention")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Spacer()
                if !hidesAttention, attentionPayment != nil {
                    Text("1 action")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(RecourseColor.ledger)
                }
            }

            if hidesAttention || attentionPayment == nil {
                protectedStatusCard
            } else {
                attentionCard
            }
        }
        .animation(.snappy(duration: 0.3), value: hidesAttention)
    }

    private var attentionCard: some View {
        HStack(spacing: 12) {
            if let payment = attentionPayment {
                MerchantArtwork(
                    payment: payment,
                    size: 58,
                    cornerRadius: 15
                )
            }

            Button {
                if let payment = attentionPayment {
                    environment.router.push(.dispute(payment.id))
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Evidence requested")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(RecourseColor.ink)
                    Text(attentionPayment.map {
                        "\($0.merchant) · \($0.orderReference)"
                    } ?? "A protected payment needs you")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RecourseColor.muted)
                        .lineLimit(2)
                    Label("Add evidence", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RecourseColor.ledger)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                hidesAttention = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RecourseColor.muted)
                    .frame(width: 28, height: 58, alignment: .top)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss attention item")
        }
        .padding(12)
        .modifier(HomeFloatingSurface(cornerRadius: 21))
    }

    private var protectedStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 18))
                .foregroundStyle(RecourseColor.ledger)
            VStack(alignment: .leading, spacing: 3) {
                Text("You're fully protected")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Text("No other payment needs you right now.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RecourseColor.muted)
            }
            Spacer()
        }
        .padding(14)
        .modifier(HomeFloatingSurface(cornerRadius: 20))
    }

    private var protectionHero: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("YOUR PROTECTION")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(RecourseColor.ledger)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(currency(protectedTotal))
                    .font(.system(size: 42, weight: .medium, design: .rounded))
                    .foregroundStyle(RecourseColor.ledger)
                Text("protected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RecourseColor.muted)
            }
            Text("Across \(activePayments.count) payments · indexed live from Arc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RecourseColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryActions: some View {
        HStack(spacing: 12) {
            Button {
                onScanRequested()
            } label: {
                Label("Pay with protection", systemImage: "arrow.up.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [RecourseColor.ledger.opacity(0.84), RecourseColor.ledger],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.42), lineWidth: 0.8)
                    }
                    .shadow(color: RecourseColor.ledger.opacity(0.24), radius: 14, y: 7)
            }
            .buttonStyle(.plain)

            Button(action: onScanRequested) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.8), lineWidth: 0.8)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 7)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan to pay")
        }
    }

    private var paymentActions: some View {
        VStack(spacing: 11) {
            primaryActions
            availableFundsLine
        }
    }

    private var availableFundsLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(RecourseColor.ledger)
                .frame(width: 7, height: 7)
            Text(availableBalanceText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(RecourseColor.muted)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(RecourseColor.muted)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var protectedNow: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Protected now", trailing: "\(activePayments.count) active")
            VStack(spacing: 8) {
                ForEach(activePayments) { payment in
                    Button {
                        environment.router.push(.payment(payment.id))
                    } label: {
                        protectedRow(payment)
                            .padding(.horizontal, 14)
                            .modifier(HomeFloatingSurface(cornerRadius: 19))
                    }
                    .buttonStyle(.plain)
                }
                if activePayments.isEmpty {
                    liveEmptyState(
                        title: "No active protections",
                        detail: "Scan a merchant checkout to create your first live protected payment."
                    )
                }
            }
        }
    }

    private func protectedRow(_ payment: DemoPayment) -> some View {
        HStack(spacing: 12) {
            MerchantArtwork(payment: payment, size: 38, cornerRadius: 11)
            VStack(alignment: .leading, spacing: 5) {
                Text(payment.merchant)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Text(payment.item)
                    .font(.system(size: 10))
                    .foregroundStyle(RecourseColor.muted)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("$\(payment.amountText.replacingOccurrences(of: " USDC", with: "")) protected")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Text(timeLeft(for: payment))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
            }
        }
        .padding(.vertical, 11)
    }

    private func timeLeft(for payment: DemoPayment) -> String {
        let days = max(1, Calendar.current.dateComponents([.day], from: Date(), to: payment.protectionEnds).day ?? 1)
        return "\(days) days left"
    }

    private var receiptsAndOutcomes: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Receipts & outcomes", trailing: "Provable")
            VStack(spacing: 0) {
                ForEach(Array(settledPayments.enumerated()), id: \.element.id) { index, payment in
                    outcomeRow(payment)
                    if index < settledPayments.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
                if settledPayments.isEmpty {
                    liveEmptyState(
                        title: "No settled receipts yet",
                        detail: "Verified outcomes will appear here after settlement."
                    )
                }
            }
        }
    }

    private func outcomeRow(_ payment: DemoPayment) -> some View {
        HStack(spacing: 13) {
            Image(systemName: payment.state == .refunded ? "arrow.uturn.backward.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 17))
                .foregroundStyle(RecourseColor.ledger)
                .frame(width: 40, height: 40)
                .background(Color(red: 0.96, green: 0.97, blue: 0.95), in: Circle())
            Button {
                environment.router.push(.payment(payment.id))
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(payment.merchant)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RecourseColor.ink)
                    Text("\(payment.state.rawValue) · \(payment.amountText)")
                        .font(.system(size: 11))
                        .foregroundStyle(RecourseColor.muted)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Recompute") {
                environment.router.push(.verdict(payment.id))
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(RecourseColor.ledger)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private func sectionTitle(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(RecourseColor.ink)
            Spacer()
            Text(trailing)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RecourseColor.muted)
        }
    }

    private var availableBalanceText: String {
        guard let balance = environment.paymentStore.balance else {
            return "Checking live USDC balance…"
        }
        return "\(balance.formatted) available to pay"
    }

    private func currency(_ amount: USDCAmount) -> String {
        let value = Double(amount.baseUnits) / Double(USDCAmount.base)
        return String(format: "$%.2f", value)
    }

    private func liveEmptyState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(RecourseColor.ink)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(RecourseColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(HomeFloatingSurface(cornerRadius: 19))
    }
}

private struct HomeFloatingSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.78), lineWidth: 0.9)
            }
            .shadow(color: RecourseColor.ledger.opacity(0.06), radius: 18, y: 9)
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}

#Preview("Buyer protection home") {
    NavigationStack {
        AppShellView(environment: .preview())
    }
    .tint(RecourseColor.ledger)
}
