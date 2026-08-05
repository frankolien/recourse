import SwiftUI

struct ReceiptsFoundationView: View {
    let environment: AppEnvironment
    let onScrollTowardTopChanged: (Bool) -> Void
    @State private var query = ""
    @State private var filter: ReceiptFilter = .all
    @State private var previousScrollOffset: CGFloat = 0

    init(
        environment: AppEnvironment,
        onScrollTowardTopChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.environment = environment
        self.onScrollTowardTopChanged = onScrollTowardTopChanged
    }

    private enum ReceiptFilter: String, CaseIterable {
        case all = "All"
        case protected = "Protected"
        case issues = "Needs attention"
        case resolved = "Resolved"
    }

    private var filteredPayments: [DemoPayment] {
        environment.paymentStore.payments.filter { payment in
            let queryMatch = query.isEmpty
                || payment.merchant.localizedCaseInsensitiveContains(query)
                || payment.item.localizedCaseInsensitiveContains(query)
                || payment.orderReference.localizedCaseInsensitiveContains(query)
            let filterMatch: Bool = switch filter {
            case .all: true
            case .protected: payment.state == .protected
            case .issues: payment.state == .actionNeeded || payment.state == .underReview
            case .resolved: payment.state == .refunded || payment.state == .released
            }
            return queryMatch && filterMatch
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 19) {
                scrollPositionReader
                pageHeader
                proofOverview
                filterBar
                receiptLedger
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 220)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .coordinateSpace(name: "recourse-receipts-scroll")
        .onPreferenceChange(RecourseScrollOffsetPreferenceKey.self) { newOffset in
            reportScrollDirection(newOffset)
        }
        .refreshable {
            await environment.paymentStore.refreshBuyer()
        }
        .task {
            await environment.paymentStore.refreshBuyer()
        }
        .background(RecourseColor.night)
    }

    private var scrollPositionReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: RecourseScrollOffsetPreferenceKey.self,
                value: proxy.frame(in: .named("recourse-receipts-scroll")).minY
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

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(RecourseColor.nightMuted)
                TextField("Search payments", text: $query)
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(RecourseColor.nightMuted)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(RecourseColor.nightChip, in: Capsule())
        }
    }

    private var proofOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Protection overview")
                .font(.recourse(18, .bold))
                .foregroundStyle(RecourseColor.nightText)
            HStack(alignment: .top, spacing: 0) {
                overviewMetric(currency(currentlyProtected), "Currently protected", "shield.fill")
                Divider().frame(height: 62).padding(.horizontal, 14)
                overviewMetric(currency(returnedToBuyer), "Returned to you", "arrow.uturn.backward")
            }
            .padding(.vertical, 6)
            Button {
                if let paymentID = environment.paymentStore.payments.first?.id {
                    environment.router.push(.verdict(paymentID))
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(RecourseColor.ledger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(environment.paymentStore.payments.count) independently reproducible receipts")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(RecourseColor.nightText)
                        Text("Verified directly from Arc")
                            .font(.recourse(10, .medium))
                            .foregroundStyle(RecourseColor.nightMuted)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(RecourseColor.ledger)
                }
                .padding(12)
                .background(RecourseColor.ledger.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func overviewMetric(_ value: String, _ caption: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
            Text(value)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(RecourseColor.nightText)
            Text(caption)
                .font(.recourse(11))
                .foregroundStyle(RecourseColor.nightMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentlyProtected: USDCAmount {
        total(for: [.protected, .actionNeeded, .underReview])
    }

    private var returnedToBuyer: USDCAmount {
        total(for: [.refunded])
    }

    private func total(for states: Set<DemoPaymentState>) -> USDCAmount {
        USDCAmount(
            baseUnits: environment.paymentStore.payments
                .filter { states.contains($0.state) }
                .reduce(0) { $0 + $1.amount.baseUnits }
        )
    }

    private func currency(_ amount: USDCAmount) -> String {
        String(
            format: "$%.2f",
            Double(amount.baseUnits) / Double(USDCAmount.base)
        )
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ReceiptFilter.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { filter = item }
                    } label: {
                        Text(item.rawValue)
                            .font(.recourse(12, .semibold))
                            .foregroundStyle(filter == item ? .white : RecourseColor.nightText)
                            .padding(.horizontal, 15)
                            .frame(height: 32)
                            .background(filter == item ? RecourseColor.ledger : RecourseColor.nightChip, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var receiptLedger: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest")
                    .font(.recourse(19, .bold))
                    .foregroundStyle(RecourseColor.nightText)
                Spacer()
                Button {} label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(RecourseColor.nightText)
                        .frame(width: 32, height: 32)
                        .background(RecourseColor.nightChip, in: Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ForEach(Array(filteredPayments.enumerated()), id: \.element.id) { index, payment in
                    Button {
                        environment.router.push(.payment(payment.id))
                    } label: {
                        WalletReceiptRow(payment: payment)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the policy, evidence, verdict, and onchain proof")
                    if index < filteredPayments.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }

            if filteredPayments.isEmpty {
                ContentUnavailableView(
                    "No matching receipts",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Try another filter or search term.")
                )
                .padding(.top, 30)
            }
        }
    }
}

private struct WalletReceiptRow: View {
    let payment: DemoPayment

    var body: some View {
        HStack(spacing: 12) {
            MerchantArtwork(payment: payment, size: 39, cornerRadius: 11)
            VStack(alignment: .leading, spacing: 4) {
                Text(payment.merchant)
                    .font(.recourse(14, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(payment.item)
                    .font(.recourse(11))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineLimit(1)
                Text(payment.state.rawValue)
                    .font(.recourse(10, .semibold))
                    .foregroundStyle(statusColor)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(currencyAmount)
                    .font(.recourse(14, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(payment.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.recourse(10))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(RecourseColor.nightMuted)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        RecourseColor.ledger
    }

    private var currencyAmount: String {
        let amount = Double(payment.amount.baseUnits) / Double(USDCAmount.base)
        return String(format: "$%.2f", amount)
    }
}

#if DEBUG
#Preview("Receipts · Wallet ledger") {
    NavigationStack {
        ReceiptsFoundationView(environment: .preview())
    }
    .tint(RecourseColor.ledger)
}
#endif
