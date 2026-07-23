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

    private var firstName: String {
        let label = environment.accountSession.account?.accountLabel ?? "Frank"
        return label.split(separator: " ").first.map(String.init) ?? "Frank"
    }

    private var activePayments: [DemoPayment] {
        allPayments.filter { $0.state == .protected || $0.state == .underReview }
    }

    private var settledPayments: [DemoPayment] {
        allPayments.filter { $0.state == .refunded || $0.state == .released }
    }

    private var allPayments: [DemoPayment] {
        environment.paymentStore.payments + DemoCatalog.payments
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                scrollPositionReader
                identityHeader
                protectionHero
                paymentActions
                attentionLead
                protectedNow
                receiptsAndOutcomes
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 164)
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(name: "recourse-home-scroll")
        .onPreferenceChange(RecourseScrollOffsetPreferenceKey.self) { newOffset in
            reportScrollDirection(newOffset)
        }
        .background(Color.white)
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
        HStack(spacing: 12) {
            Button {
                environment.router.push(.account)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Text(firstName.prefix(1).uppercased())
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(RecourseColor.ledgerDeep, in: Circle())

                    Image(systemName: "shield.checkered")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(RecourseColor.ledgerDeep)
                        .frame(width: 18, height: 18)
                        .background(.white, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open profile")

            VStack(alignment: .leading, spacing: 3) {
                Text("@\(firstName.lowercased())")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("Protected on Arc Testnet")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(RecourseColor.muted)
                }
            }

            Spacer()

            Button {
                environment.router.push(.verdict(268))
            } label: {
                headerAction("Verify", systemImage: "checkmark.seal.fill")
            }
            .buttonStyle(.plain)

            Button {
                environment.router.push(.support)
            } label: {
                ZStack(alignment: .topTrailing) {
                    headerAction("Alerts", systemImage: "bell")
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: -5, y: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notifications")
        }
    }

    private func headerAction(_ label: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(height: 18)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(RecourseColor.ink)
        .frame(width: 42, height: 42)
    }

    private var attentionLead: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(hidesAttention ? "Protection status" : "Needs your attention")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Spacer()
                if !hidesAttention {
                    Text("1 action")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.orange)
                }
            }

            if hidesAttention {
                protectedStatusCard
            } else {
                attentionCard
            }
        }
        .animation(.snappy(duration: 0.3), value: hidesAttention)
    }

    private var attentionCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.93, green: 0.93, blue: 0.92))
                .offset(y: 10)
                .padding(.horizontal, 10)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.965, green: 0.965, blue: 0.955))
                .offset(y: 5)
                .padding(.horizontal, 5)

            HStack(spacing: 14) {
                MerchantArtwork(
                    payment: DemoCatalog.payment(id: 284),
                    size: 72,
                    cornerRadius: 18
                )

                Button {
                    environment.router.push(.dispute(284))
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Evidence requested")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(RecourseColor.ink)
                        Text("MegaStore · due today at 5:00 PM")
                            .font(.system(size: 12, weight: .medium))
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RecourseColor.ink)
                        .frame(width: 32, height: 72, alignment: .top)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss attention item")
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(red: 0.86, green: 0.86, blue: 0.85), lineWidth: 1)
            }
        }
        .padding(.bottom, 10)
    }

    private var protectedStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 20))
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
        .padding(16)
        .background(Color(red: 0.965, green: 0.975, blue: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var protectionHero: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("YOUR PROTECTION")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(RecourseColor.ledger)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("$464.00")
                    .font(.system(size: 46, weight: .medium, design: .rounded))
                    .foregroundStyle(RecourseColor.ink)
                Text("protected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RecourseColor.muted)
            }
            Text("Across 3 payments · all policies active")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RecourseColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryActions: some View {
        HStack(spacing: 12) {
            Button {
                environment.router.push(.checkout(DemoCatalog.checkoutRequest(configuration: environment.configuration)))
            } label: {
                Label("Pay with protection", systemImage: "arrow.up.right")
                    .font(.system(size: 17, weight: .medium ))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(RecourseColor.ink, in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onScanRequested) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(RecourseColor.ink)
                    .frame(width: 58, height: 58)
                    .background(Color(red: 0.95, green: 0.95, blue: 0.94), in: Circle())
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
                .fill(Color.green)
                .frame(width: 7, height: 7)
            Text("2,480.50 USDC available to pay")
                .font(.system(size: 12, weight: .medium))
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
            VStack(spacing: 0) {
                ForEach(Array(activePayments.enumerated()), id: \.element.id) { index, payment in
                    Button {
                        environment.router.push(.payment(payment.id))
                    } label: {
                        protectedRow(payment)
                    }
                    .buttonStyle(.plain)
                    if index < activePayments.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .padding(.horizontal, 15)
            .background(Color(red: 0.975, green: 0.975, blue: 0.965), in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private func protectedRow(_ payment: DemoPayment) -> some View {
        HStack(spacing: 14) {
            MerchantArtwork(payment: payment, size: 43, cornerRadius: 13)
            VStack(alignment: .leading, spacing: 5) {
                Text(payment.merchant)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Text(payment.item)
                    .font(.system(size: 11))
                    .foregroundStyle(RecourseColor.muted)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("$\(payment.amountText.replacingOccurrences(of: " USDC", with: "")) protected")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Text(timeLeft(for: payment))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
            }
        }
        .padding(.vertical, 14)
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
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(RecourseColor.ink)
            Spacer()
            Text(trailing)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RecourseColor.muted)
        }
    }
}

#Preview("Buyer protection home") {
    NavigationStack {
        AppShellView(environment: .preview())
    }
    .tint(RecourseColor.ledger)
}
