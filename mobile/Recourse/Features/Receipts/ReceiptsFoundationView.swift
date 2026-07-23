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
        (environment.paymentStore.payments + DemoCatalog.payments).filter { payment in
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
            LazyVStack(alignment: .leading, spacing: 24) {
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
        .coordinateSpace(name: "recourse-receipts-scroll")
        .onPreferenceChange(RecourseScrollOffsetPreferenceKey.self) { newOffset in
            reportScrollDirection(newOffset)
        }
        .background(Color.white)
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(RecourseColor.muted)
                TextField("Search payments", text: $query)
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(RecourseColor.muted)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Color(red: 0.96, green: 0.96, blue: 0.95), in: Capsule())
        }
    }

    private var proofOverview: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Protection overview")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(RecourseColor.ink)
            HStack(alignment: .top, spacing: 0) {
                overviewMetric("$464.00", "Currently protected", "shield.fill")
                Divider().frame(height: 72).padding(.horizontal, 18)
                overviewMetric("$84.50", "Returned to you", "arrow.uturn.backward")
            }
            .padding(.vertical, 6)
            Button {
                environment.router.push(.verdict(268))
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(RecourseColor.ledger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("6 independently reproducible receipts")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(RecourseColor.ink)
                        Text("Verified directly from Arc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(RecourseColor.muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(RecourseColor.ledger)
                }
                .padding(14)
                .background(RecourseColor.softGreen, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
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
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(RecourseColor.ink)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(RecourseColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ReceiptFilter.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { filter = item }
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(filter == item ? .white : RecourseColor.ink)
                            .padding(.horizontal, 15)
                            .frame(height: 36)
                            .background(filter == item ? RecourseColor.ink : Color(red: 0.96, green: 0.96, blue: 0.95), in: Capsule())
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
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Spacer()
                Button {} label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(RecourseColor.ink)
                        .frame(width: 36, height: 36)
                        .background(Color(red: 0.96, green: 0.96, blue: 0.95), in: Circle())
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
        HStack(spacing: 14) {
            MerchantArtwork(payment: payment, size: 44, cornerRadius: 13)
            VStack(alignment: .leading, spacing: 4) {
                Text(payment.merchant)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RecourseColor.ink)
                Text(payment.item)
                    .font(.system(size: 12))
                    .foregroundStyle(RecourseColor.muted)
                    .lineLimit(1)
                Text(payment.state.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(currencyAmount)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RecourseColor.ink)
                Text(payment.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10))
                    .foregroundStyle(RecourseColor.muted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(RecourseColor.muted)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        payment.state == .actionNeeded ? .orange : payment.state == .underReview ? .blue : RecourseColor.ledger
    }

    private var currencyAmount: String {
        let amount = Double(payment.amount.baseUnits) / Double(USDCAmount.base)
        return String(format: "$%.2f", amount)
    }
}

#Preview("Receipts · Wallet ledger") {
    NavigationStack {
        ReceiptsFoundationView(environment: .preview())
    }
    .tint(RecourseColor.ledger)
}
