import SwiftUI

struct HomeView: View {
    let environment: AppEnvironment
    let onScrollTowardTopChanged: (Bool) -> Void
    let onScanRequested: () -> Void
    let onEarnRequested: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var previousScrollOffset: CGFloat = 0
    @State private var hidesAttention = false
    @State private var showsReceive = false
    @State private var earnVaultState: VaultState?
    @AppStorage("recourse.hidesBalance") private var hidesBalance = false

    init(
        environment: AppEnvironment,
        onScrollTowardTopChanged: @escaping (Bool) -> Void = { _ in },
        onScanRequested: @escaping () -> Void = {},
        onEarnRequested: @escaping () -> Void = {}
    ) {
        self.environment = environment
        self.onScrollTowardTopChanged = onScrollTowardTopChanged
        self.onScanRequested = onScanRequested
        self.onEarnRequested = onEarnRequested
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
                    actionGrid
                    if attentionPayment != nil && !hidesAttention {
                        attentionLead
                    }
                    earnPreview
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
            // No opaque fill: the canvas glow must run uninterrupted behind the
            // header, otherwise the boundary reads as a seam.
            identityHeader
                .padding(.horizontal, 20)
                .frame(height: 72)
        }
        .coordinateSpace(name: "recourse-home-scroll")
        .onPreferenceChange(RecourseScrollOffsetPreferenceKey.self) { newOffset in
            reportScrollDirection(newOffset)
        }
        .sheet(isPresented: $showsReceive) {
            ReceiveSheet(environment: environment)
                .presentationDetents([.medium, .large])
        }
        .task {
            while !Task.isCancelled {
                await environment.paymentStore.refreshBuyer()
                // Reminders track the refreshed list so settled payments drop
                // theirs and new protected payments gain one, no screen visit needed.
                await DisputeReminderScheduler.sync(
                    payments: environment.paymentStore.payments,
                    enabled: UserDefaults.standard.object(forKey: BuyerSettingKey.disputeDeadlineReminders) == nil
                        || UserDefaults.standard.bool(forKey: BuyerSettingKey.disputeDeadlineReminders)
                )
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .task {
            // One live snapshot for the Earn teaser; the Earn screen itself
            // refreshes on every visit.
            guard let owner = try? await environment.buyerSigner.address(),
                  let gateway = try? environment.makeContractGateway() else { return }
            earnVaultState = try? await gateway.vaultState(of: owner)
        }
    }

    // Flat ground; in the dark appearance a soft brand glow bleeds from the top.
    private var homeCanvas: some View {
        ZStack(alignment: .top) {
            RecourseColor.night
            if colorScheme == .dark {
                LinearGradient(
                    colors: [RecourseColor.ledgerDeep.opacity(0.32), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 320)
            }
        }
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
                    .foregroundStyle(RecourseColor.nightText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open profile")

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(RecourseColor.nightText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                HStack(spacing: 5) {
                    Image("ArcMark")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 10)
                    Text("Protected on Arc Testnet")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }

            Spacer()

            Button {
                environment.router.push(.support)
            } label: {
                ZStack(alignment: .topTrailing) {
                    headerAction(title: "Alerts", systemImage: "bell")
                    Circle()
                        .fill(RecourseColor.ledger)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(RecourseColor.night, lineWidth: 1.5))
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
        .foregroundStyle(RecourseColor.nightText)
    }

    private var attentionLead: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Needs your attention")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RecourseColor.nightText)
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
                        .foregroundStyle(RecourseColor.nightText)
                    Text(attentionPayment.map {
                        "\($0.merchant) · \($0.orderReference)"
                    } ?? "A protected payment needs you")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
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
                    .foregroundStyle(RecourseColor.nightMuted)
                    .frame(width: 28, height: 58, alignment: .top)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss attention item")
        }
        .padding(12)
        .modifier(HomeFloatingSurface(cornerRadius: 21))
    }

    // Bank-app hierarchy: the balance owns the screen and the protection line
    // sits where other money apps put the daily delta, in the brand green when
    // money is actually protected. Tapping the block toggles balance privacy,
    // and the number swaps through a blur so hiding feels like a shutter, not
    // a flicker; the choice persists because glancing in public is a habit.
    private var protectionHero: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Slow on purpose: the number should dissolve like a slide fading
            // over, not snap like a checkbox.
            withAnimation(.smooth(duration: 0.75)) {
                hidesBalance.toggle()
            }
        } label: {
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    Text("USDC · Arc Testnet")
                    Image(systemName: hidesBalance ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RecourseColor.nightMuted)

                ZStack {
                    if hidesBalance {
                        Text("$••••")
                            .transition(.blurReplace)
                    } else {
                        Text(balanceHeadline)
                            .transition(.blurReplace)
                    }
                }
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .foregroundStyle(RecourseColor.nightText)
                .minimumScaleFactor(0.55)
                .lineLimit(1)

                Text(heroSubtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(activePayments.isEmpty ? RecourseColor.nightMuted : RecourseColor.ledger)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hidesBalance ? "Show balance" : "Hide balance")
        .padding(.top, 20)
        .padding(.bottom, 2)
    }

    private var balanceHeadline: String {
        guard let balance = environment.paymentStore.balance else { return "$—" }
        return currency(balance)
    }

    private var heroSubtitle: String {
        if activePayments.isEmpty {
            return "Nothing protected yet"
        }
        // Privacy covers every amount on the hero, not just the headline.
        let amount = hidesBalance ? "$••••" : currency(protectedTotal)
        return "\(amount) protected · \(activePayments.count) active"
    }

    // Banking verbs in soft square tiles, one row, with Pay carrying the
    // accent the way top money apps color their hero verb. Pay is the only
    // scan entry in the app, so no icon appears twice on this screen; Earn
    // lives in the tab bar now and Verify takes its tile back.
    private var actionGrid: some View {
        HStack(spacing: 12) {
            actionTile("plus", "Add money") {
                showsReceive = true
            }
            actionTile("paperplane.fill", "Send") {
                environment.router.push(.send)
            }
            actionTile("checkmark.seal.fill", "Verify") {
                if let paymentID = settledPayments.first?.id ?? allPayments.first?.id {
                    environment.router.push(.verdict(paymentID))
                }
            }
            actionTile("qrcode.viewfinder", "Pay", accent: true, action: onScanRequested)
        }
    }

    private func actionTile(
        _ systemImage: String,
        _ title: String,
        accent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(accent ? .white : RecourseColor.nightText)
                    .frame(width: 58, height: 58)
                    .background(
                        accent ? RecourseColor.ledger : RecourseColor.nightChip,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RecourseColor.nightText)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent ? "Pay with protection" : title)
    }

    private var earnPreview: some View {
        Button {
            onEarnRequested()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .frame(width: 38, height: 38)
                    .background(RecourseColor.nightChip, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(earnPreviewTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RecourseColor.nightText)
                    Text(earnPreviewDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            .padding(14)
            .contentShape(Rectangle())
            .modifier(HomeFloatingSurface(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var earnPreviewTitle: String {
        if let earnVaultState, earnVaultState.myShares > 0 {
            return "Your Earn position"
        }
        return "Earn on idle USDC"
    }

    private var earnPreviewDetail: String {
        guard let earnVaultState else {
            return "Fund instant merchant settlements, collect fees and yield"
        }
        if earnVaultState.myShares > 0 {
            return "\(currency(earnVaultState.myValue)) · share price \(String(format: "%.4f", earnVaultState.sharePrice))"
        }
        return "\(currency(earnVaultState.totalAssets)) in the vault · share price \(String(format: "%.4f", earnVaultState.sharePrice))"
    }

    private var firstStepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How your first payment works")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(RecourseColor.nightText)
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
                .foregroundStyle(RecourseColor.nightText)
                .frame(width: 34, height: 34)
                .background(RecourseColor.nightChip, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(RecourseColor.nightMuted)
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
                    .foregroundStyle(RecourseColor.nightText)
                Text(payment.item)
                    .font(.system(size: 10))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("$\(payment.amountText.replacingOccurrences(of: " USDC", with: "")) protected")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(timeLeft(for: payment))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(RecourseColor.nightMuted)
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
                .foregroundStyle(payment.state == .refunded ? RecourseColor.ledger : RecourseColor.nightText)
                .frame(width: 40, height: 40)
                .background(RecourseColor.nightChip, in: Circle())
            Button {
                environment.router.push(.payment(payment.id))
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(payment.merchant)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                    Text("\(payment.state.rawValue) · \(payment.amountText)")
                        .font(.system(size: 11))
                        .foregroundStyle(RecourseColor.nightMuted)
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
                .foregroundStyle(RecourseColor.nightText)
            Spacer()
            Text(trailing)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RecourseColor.nightMuted)
        }
    }

    private func currency(_ amount: USDCAmount) -> String {
        let value = Double(amount.baseUnits) / Double(USDCAmount.base)
        return String(format: "$%.2f", value)
    }
}

// Sections sit directly on the black ground; the old floating box is gone on
// purpose, so this only keeps the corner clip for tap highlights.
private struct HomeFloatingSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
