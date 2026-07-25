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
                LazyVStack(alignment: .leading, spacing: 18) {
                    scrollPositionReader
                    protectionHero
                    if attentionPayment != nil && !hidesAttention {
                        attentionLead
                    }
                    // A fresh account gets one guided card, not a stack of empty
                    // section shells; sections appear as soon as they have content.
                    if allPayments.isEmpty {
                        firstStepsCard
                    }
                    if !activePayments.isEmpty {
                        protectedNow
                    }
                    if !settledPayments.isEmpty {
                        receiptsAndOutcomes
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
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
                Text("Needs your attention")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RecourseColor.ink)
                Spacer()
                Text("1 action")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(RecourseColor.ledger)
            }
            attentionCard
        }
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

    // One composed wallet card carrying the number, the live balance, and every
    // action; it mirrors the merchant hero so both roles share one visual family.
    private var protectionHero: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(RecourseColor.ledger.opacity(0.1))
                .frame(width: 170, height: 170)
                .blur(radius: 46)
                .offset(x: 54, y: -62)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Your protection", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text("ARC TESTNET")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.35)
                        .foregroundStyle(.white.opacity(0.68))
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(currency(protectedTotal))
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.72)
                        Text("protected")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    Text(heroSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                }
                heroActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(RecourseColor.ink, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: RecourseColor.ink.opacity(0.15), radius: 18, y: 10)
    }

    private var heroSubtitle: String {
        guard let balance = environment.paymentStore.balance else {
            return "Checking live USDC balance…"
        }
        if activePayments.isEmpty {
            return "\(balance.formatted) ready to spend"
        }
        return "\(activePayments.count) active · \(balance.formatted) to spend"
    }

    private var heroActions: some View {
        HStack(spacing: 10) {
            Button(action: onScanRequested) {
                Label("Pay with protection", systemImage: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)

            heroCircleButton("qrcode.viewfinder", label: "Scan to pay", action: onScanRequested)
            heroCircleButton("paperplane.fill", label: "Send USDC") {
                environment.router.push(.send)
            }
        }
    }

    private func heroCircleButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.white.opacity(0.12), in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.16), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var firstStepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How your first payment works")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(RecourseColor.ink)
            firstStep("qrcode.viewfinder", "Scan a merchant checkout", "Recourse QRs open here, straight from the Camera app too.")
            firstStep("lock.shield.fill", "USDC escrows under the policy", "Refund rules are locked onchain before any funds move.")
            firstStep("checkmark.seal.fill", "Every outcome is provable", "Refunds compute from evidence, and you can verify the result yourself.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .modifier(HomeFloatingSurface(cornerRadius: 21))
    }

    private func firstStep(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RecourseColor.ink)
                .frame(width: 34, height: 34)
                .background(RecourseColor.clay, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(RecourseColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
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
                    .foregroundStyle(RecourseColor.muted)
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
            }
        }
    }

    private func outcomeRow(_ payment: DemoPayment) -> some View {
        HStack(spacing: 13) {
            Image(systemName: payment.state == .refunded ? "arrow.uturn.backward.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 17))
                // Green only when money came back; a completed sale is a neutral fact.
                .foregroundStyle(payment.state == .refunded ? RecourseColor.ledger : RecourseColor.ink)
                .frame(width: 40, height: 40)
                .background(RecourseColor.clay, in: Circle())
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RecourseColor.ink)
            Spacer()
            Text(trailing)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RecourseColor.muted)
        }
    }

    private func currency(_ amount: USDCAmount) -> String {
        let value = Double(amount.baseUnits) / Double(USDCAmount.base)
        return String(format: "$%.2f", value)
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

#if DEBUG
#Preview("Buyer protection home") {
    NavigationStack {
        AppShellView(environment: .preview())
    }
    .tint(RecourseColor.ledger)
}
#endif
