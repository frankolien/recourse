import SwiftUI

/// Everything that has happened, in one list.
///
/// It replaces the Receipts tab, which was a protection ledger: currently protected,
/// returned to you, filed disputes. None of that exists any more. What a wallet owes
/// you instead is the plain question "what happened to my money", answered in the
/// order it happened.
///
/// Cheques are the only entries so far, because they are the only movements the app
/// records rather than infers. A plain send is a chain transfer with nothing written
/// down beside it, and inventing a history for those would mean indexing transfers,
/// which is a different job than this screen.
struct ActivityView: View {
    let environment: AppEnvironment
    let onScrollTowardTopChanged: (Bool) -> Void
    @State private var previousScrollOffset: CGFloat = 0
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var names: [String: String] = [:]
    @State private var selected: Entry?

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

    /// A cheque plus which side of it this account is on, which decides everything the
    /// row says: the direction, the sign, and whose name to print.
    private struct Entry: Identifiable, Equatable {
        let cheque: ChequeEntry
        let mine: Bool

        var id: String { "\(mine ? "w" : "r")-\(cheque.id)" }
        var counterparty: String { mine ? cheque.stored.to : cheque.stored.from }
        var date: Date { cheque.stored.expiresAt }
    }

    private var book: ChequeBook { environment.chequeBook }

    private var entries: [Entry] {
        let all = book.received.map { Entry(cheque: $0, mine: false) }
            + book.written.map { Entry(cheque: $0, mine: true) }
        return all
            .filter { entry in
                let matchesFilter = switch filter {
                case .all: true
                case .incoming: !entry.mine
                case .outgoing: entry.mine
                }
                guard matchesFilter else { return false }
                guard !query.isEmpty else { return true }
                let memo = entry.cheque.stored.memo ?? ""
                return name(for: entry).localizedCaseInsensitiveContains(query)
                    || memo.localizedCaseInsensitiveContains(query)
                    || entry.cheque.stored.usdc.decimalString.contains(query)
            }
            // Newest first, by cheque id: created_at ordering already comes back that
            // way per side, and the id is the only field that orders the merge.
            .sorted { $0.cheque.id > $1.cheque.id }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                scrollPositionReader
                searchField
                    .padding(.bottom, 16)
                filterBar
                    .padding(.bottom, 8)

                if entries.isEmpty {
                    empty
                } else {
                    ForEach(entries) { entry in
                        Button {
                            selected = entry
                        } label: {
                            row(entry)
                        }
                        .buttonStyle(.plain)
                        if entry.id != entries.last?.id {
                            Divider()
                                .overlay(RecourseColor.nightLine)
                                .padding(.leading, 56)
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
        .refreshable {
            await reload(force: true)
        }
        .sheet(item: $selected) { entry in
            ChequeDetailView(
                entry: entry.cheque,
                counterpartyName: name(for: entry),
                mine: entry.mine,
                environment: environment
            )
            .presentationDetents([.large])
            .presentationBackground(RecourseColor.night)
        }
        .task {
            await reload(force: false)
        }
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
            TextField("Search by name, memo or amount", text: $query)
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

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: 13) {
            Image(systemName: glyph(for: entry))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(entry.cheque.standing.isLive ? RecourseColor.ledger : RecourseColor.nightMuted)
                .frame(width: 42, height: 42)
                .background(RecourseColor.nightChip, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(name(for: entry))
                    .font(.recourse(14, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .lineLimit(1)
                Text(subtitle(for: entry))
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                // Signed, because direction is the first thing anyone reads in a
                // transaction list, and only green when money actually came in.
                Text("\(entry.mine ? "-" : "+")\(entry.cheque.stored.usdc.decimalString)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(amountInk(for: entry))
                    .strikethrough(
                        entry.cheque.standing == .voided || entry.cheque.standing == .expired,
                        color: RecourseColor.nightMuted
                    )
                Text(standingText(entry))
                    .font(.recourse(10, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(query.isEmpty ? "Nothing here yet" : "No matches")
                .font(.recourse(15, .semibold))
                .foregroundStyle(RecourseColor.nightText)
            Text(
                query.isEmpty
                    ? "Cheques you write and cheques written to you show up here, with what happened to each one."
                    : "Try a different name, memo or amount."
            )
            .font(.recourse(12.5))
            .foregroundStyle(RecourseColor.nightMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 30)
        .padding(.trailing, 24)
    }

    // MARK: Copy

    private func glyph(for entry: Entry) -> String {
        switch entry.cheque.standing {
        case .cashable: entry.mine ? "clock.fill" : "arrow.down.circle.fill"
        case .notYet: "clock.badge.fill"
        case .expired: "clock.badge.xmark.fill"
        case .cashed: "checkmark.circle.fill"
        case .voided: "xmark.circle.fill"
        }
    }

    private func amountInk(for entry: Entry) -> Color {
        switch entry.cheque.standing {
        case .cashable: entry.mine ? RecourseColor.nightText : RecourseColor.ledger
        case .cashed: entry.mine ? RecourseColor.nightText : RecourseColor.ledger
        case .notYet, .expired, .voided: RecourseColor.nightMuted
        }
    }

    private func standingText(_ entry: Entry) -> String {
        switch entry.cheque.standing {
        case .cashable: entry.mine ? "Outstanding" : "Ready"
        case .notYet(let from): "From \(from.formatted(date: .abbreviated, time: .omitted))"
        case .expired: "Expired"
        case .cashed: "Cashed"
        case .voided: "Voided"
        }
    }

    private func subtitle(for entry: Entry) -> String {
        if let memo = entry.cheque.stored.memo, !memo.isEmpty { return memo }
        return entry.mine ? "Cheque you wrote" : "Cheque written to you"
    }

    private func name(for entry: Entry) -> String {
        if let handle = names[entry.counterparty.lowercased()] { return "@\(handle)" }
        return EthereumAddress(trusted: entry.counterparty).shortened
    }

    private func reload(force: Bool) async {
        await book.refresh(force: force)
        await resolveNames()
    }

    /// One batched lookup for every address on screen, so a page of activity is one
    /// request rather than one per row.
    private func resolveNames() async {
        let addresses = book.received.map(\.stored.from) + book.written.map(\.stored.to)
        guard !addresses.isEmpty else { return }
        if let found = try? await environment.makeHandleAPIClient().names(for: addresses) {
            names = found
        }
    }
}
