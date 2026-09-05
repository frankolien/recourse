import SwiftUI

/// Everything that moved money, in the order it moved.
///
/// The spine is the explorer's list of transfers, which is the only complete record: a
/// plain send from a hardware wallet into this one belongs here as much as a cheque
/// does, and nothing in this app ever saw it happen. Each movement is then named from
/// the function that made it and who was on the other end, so a cheque reads as a
/// cheque and a conversion as a conversion rather than as two transfers.
struct ActivityView: View {
    let environment: AppEnvironment
    let onScrollTowardTopChanged: (Bool) -> Void
    @State private var openedTransaction: WebPageLink?
    @State private var previousScrollOffset: CGFloat = 0
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var names: [String: String] = [:]

    init(
        environment: AppEnvironment,
        onScrollTowardTopChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.environment = environment
        self.onScrollTowardTopChanged = onScrollTowardTopChanged
    }

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case incoming = "In"
        case outgoing = "Out"
        var id: String { rawValue }
    }

    private var history: TransferHistory { environment.transferHistory }
    private var usdcAddress: String { environment.configuration.usdcAddress.value.lowercased() }

    private var entries: [HistoryEntry] {
        history.entries(
            invoicePayers: Set(environment.invoiceBook.issued.map { $0.stored.payer.lowercased() }),
            invoiceIssuers: Set(environment.invoiceBook.received.map { $0.stored.issuer.lowercased() })
        )
        .filter { entry in
            let matchesFilter = switch filter {
            case .all: true
            case .incoming: entry.incoming
            case .outgoing: !entry.incoming
            }
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return name(for: entry).localizedCaseInsensitiveContains(query)
                || entry.kind.title.localizedCaseInsensitiveContains(query)
                || amountText(entry).contains(query)
        }
    }

    /// One calendar day of movements, newest day first, as the list's section.
    private struct Day: Identifiable {
        let start: Date
        let title: String
        let entries: [HistoryEntry]
        var id: Date { start }
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.transfer.timestamp) }
        return grouped.keys.sorted(by: >).map { start in
            Day(start: start, title: dayTitle(start, calendar: calendar), entries: grouped[start] ?? [])
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                scrollPositionReader
                searchField
                    .padding(.bottom, 16)
                filterBar

                if entries.isEmpty {
                    empty
                } else {
                    ForEach(days) { day in
                        Text(day.title)
                            .font(.recourse(12.5, .semibold))
                            .foregroundStyle(RecourseColor.nightMuted)
                            .padding(.top, 18)
                            .padding(.bottom, 4)
                        ForEach(day.entries) { entry in
                            Button {
                                openedTransaction = WebPageLink(
                                    url: AppConfiguration.explorerURL.appending(path: "tx/\(entry.transfer.hash)")
                                )
                            } label: {
                                row(entry)
                            }
                            .buttonStyle(.plain)
                            if entry.id != day.entries.last?.id {
                                Divider()
                                    .overlay(RecourseColor.nightLine)
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 200)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .coordinateSpace(name: "recourse-activity-scroll")
        .onPreferenceChange(RecourseScrollOffsetPreferenceKey.self) { newOffset in
            reportScrollDirection(newOffset)
        }
        .background(RecourseColor.night)
        .navigationTitle("History")
        // The explorer opens in a sheet, the way the faucet does, so a look at a
        // transaction never bounces the user out to Safari.
        .sheet(item: $openedTransaction) { page in
            SafariWebView(url: page.url)
        }
        .refreshable { await reload(force: true) }
        .task { await reload(force: false) }
    }

    private var scrollPositionReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: RecourseScrollOffsetPreferenceKey.self,
                value: proxy.frame(in: .named("recourse-activity-scroll")).minY
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

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RecourseColor.nightMuted)
            TextField("Search by name, kind or amount", text: $query)
                .font(.recourse(14, .medium))
                .foregroundStyle(RecourseColor.nightText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .recourseGlassField(cornerRadius: 23)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases) { option in
                Button {
                    guard filter != option else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy(duration: 0.2)) { filter = option }
                } label: {
                    Text(option.rawValue)
                        .font(.recourse(12.5, .semibold))
                        .foregroundStyle(filter == option ? .white : RecourseColor.nightMuted)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background {
                            if filter == option {
                                Capsule().fill(RecourseColor.ledger)
                            } else {
                                Capsule().stroke(RecourseColor.nightLine, lineWidth: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 13) {
            // The coin first, because the first question about a row is "which money",
            // and the direction rides on it as a badge the way a home-screen icon
            // carries a count.
            BrandMarkView(mark: entry.transfer.token == usdcAddress ? .usdc : .eurc, height: 42)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: entry.kind.symbol)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(entry.incoming ? RecourseColor.ledger : RecourseColor.nightText)
                        .frame(width: 18, height: 18)
                        .background(RecourseColor.nightChip, in: Circle())
                        .overlay(Circle().stroke(RecourseColor.night, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(name(for: entry))
                    .font(.recourse(14, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .lineLimit(1)
                // Time only: the day is the section header above the row.
                Text("\(entry.kind.title) · \(entry.transfer.timestamp.formatted(.dateTime.hour().minute()))")
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(entry.incoming ? "+" : "-")\(amountText(entry)) \(entry.transfer.symbol)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(entry.incoming ? RecourseColor.ledger : RecourseColor.nightText)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // An explorer that did not answer is not an empty wallet, so the empty state
    // says which one it is.
    private var unreachable: Bool { query.isEmpty && history.errorMessage != nil }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(unreachable ? "History could not be loaded" : query.isEmpty ? "Nothing yet" : "No matches")
                .font(.recourse(15, .semibold))
                .foregroundStyle(RecourseColor.nightText)
            Text(
                unreachable
                    ? "Arc is not answering. Pull down to try again."
                    : query.isEmpty
                        ? "Every dollar that moves in or out of this wallet lands here, whatever moved it."
                        : "Try a different name, kind or amount."
            )
            .font(.recourse(12.5))
            .foregroundStyle(RecourseColor.nightMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 30)
        .padding(.trailing, 24)
    }

    // MARK: Copy

    /// Today and yesterday by name, the rest by date, with the year only once it differs.
    private func dayTitle(_ start: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(start) { return "Today" }
        if calendar.isDateInYesterday(start) { return "Yesterday" }
        if calendar.isDate(start, equalTo: .now, toGranularity: .year) {
            return start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return start.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func amountText(_ entry: HistoryEntry) -> String {
        USDCAmount(baseUnits: entry.transfer.value).decimalString
    }

    /// The other party, named where the directory knows them, and named for what they
    /// are where they are one of ours.
    private func name(for entry: HistoryEntry) -> String {
        switch entry.kind {
        case .earnDeposit, .earnWithdrawal: return "Earn"
        case .converted: return "Convert"
        case .escrow: return "Recourse escrow"
        default: break
        }
        if let handle = names[entry.counterparty] { return "@\(handle)" }
        return EthereumAddress(trusted: entry.counterparty).shortened
    }

    private func reload(force: Bool) async {
        await history.refresh(force: force)
        await environment.invoiceBook.refresh(force: force)
        await resolveNames()
    }

    private func resolveNames() async {
        let addresses = Array(Set(history.transfers.flatMap { [$0.from, $0.to] })).prefix(50)
        guard !addresses.isEmpty else { return }
        if let found = try? await environment.makeHandleAPIClient().names(for: Array(addresses)) {
            names = found
        }
    }
}
