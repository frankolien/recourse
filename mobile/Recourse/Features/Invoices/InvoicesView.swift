import SwiftUI

/// Money in both directions: what you are owed, and what you owe.
///
/// Two sides rather than one list, because they carry opposite obligations and a
/// combined total would mean nothing. The side you are on also decides the only action
/// available: you collect what has been signed for you, and you answer what has been
/// asked of you.
struct InvoicesView: View {
    let environment: AppEnvironment

    private enum Side: String, CaseIterable, Identifiable {
        case owed
        case owing

        var id: String { rawValue }
        var title: String {
            switch self {
            case .owed: "Owed to you"
            case .owing: "You owe"
            }
        }
    }

    @State private var side: Side = .owed
    @State private var names: [String: String] = [:]
    @State private var selected: InvoiceEntry?

    private var book: InvoiceBook { environment.invoiceBook }

    private var entries: [InvoiceEntry] {
        side == .owed ? book.issued : book.received
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                summary
                    .padding(.bottom, 22)
                sideSwitch
                    .padding(.bottom, 18)

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
            .padding(.top, 6)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await reload(force: true)
        }
        .safeAreaInset(edge: .bottom) {
            requestBar
        }
        .sheet(item: $selected) { entry in
            InvoiceDetailView(
                entry: entry,
                counterpartyName: name(for: entry),
                mine: side == .owed,
                environment: environment
            )
            .presentationDetents([.large])
            .presentationBackground(RecourseColor.night)
        }
        .task {
            await reload(force: false)
        }
    }

    // MARK: Sections

    private var summary: some View {
        HStack(alignment: .top, spacing: 0) {
            figure(
                label: "Owed to you",
                amount: book.owedToYou,
                detail: readyDetail,
                accent: !book.readyToCollect.isEmpty
            )
            Rectangle()
                .fill(RecourseColor.nightLine)
                .frame(width: 1, height: 44)
                .padding(.horizontal, 18)
            figure(
                label: "You owe",
                amount: book.youOwe,
                detail: book.awaitingYou.count == 1 ? "1 to answer" : "\(book.awaitingYou.count) to answer",
                accent: false
            )
        }
        .padding(.top, 10)
    }

    /// The collectable total is the one with something to do about it, so it is what
    /// the caption says when there is any.
    private var readyDetail: String {
        let ready = book.readyToCollect.count
        guard ready > 0 else {
            return book.issued.filter(\.standing.isLive).count == 1 ? "1 open" : "\(book.issued.filter(\.standing.isLive).count) open"
        }
        return ready == 1 ? "1 ready to collect" : "\(ready) ready to collect"
    }

    private func figure(label: String, amount: USDCAmount, detail: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.recourse(10, .semibold))
                .kerning(1.1)
                .foregroundStyle(RecourseColor.nightMuted)
            Text(amount.decimalString)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .foregroundStyle(accent ? RecourseColor.ledger : RecourseColor.nightText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(detail)
                .font(.recourse(11, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sideSwitch: some View {
        HStack(spacing: 6) {
            ForEach(Side.allCases) { option in
                Button {
                    guard side != option else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy(duration: 0.22)) { side = option }
                } label: {
                    Text(option.title)
                        .font(.recourse(13, .semibold))
                        .foregroundStyle(side == option ? RecourseColor.nightText : RecourseColor.nightMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background {
                    if side == option {
                        Capsule().fill(RecourseColor.nightChip)
                    }
                }
            }
        }
        .padding(4)
        .recourseGlassField(cornerRadius: 24)
    }

    private func row(_ entry: InvoiceEntry) -> some View {
        HStack(spacing: 13) {
            Image(systemName: glyph(for: entry))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink(for: entry))
                .frame(width: 42, height: 42)
                .background(RecourseColor.nightChip, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(name(for: entry))
                    .font(.recourse(14, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .lineLimit(1)
                Text(entry.stored.memo)
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.stored.usdc.decimalString)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink(for: entry))
                    .strikethrough(
                        entry.standing == .cancelled || entry.standing == .overdue || entry.standing == .lapsed,
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

    @ViewBuilder
    // A server that did not answer is not an empty list, so the empty state says
    // which one it is.
    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                book.errorMessage != nil
                    ? "Invoices could not be loaded"
                    : side == .owed ? "You have not asked for anything" : "Nobody has billed you"
            )
            .font(.recourse(15, .semibold))
            .foregroundStyle(RecourseColor.nightText)
            Text(
                book.errorMessage != nil
                    ? "Recourse is not answering. Pull down to try again."
                    : side == .owed
                        ? "An invoice fixes the amount, the date and who pays before they ever see it. They answer with a signature, and you collect whenever you like."
                        : "When someone bills you it lands here. Paying is one signature, it costs you no gas, and the amount can never be changed after you sign."
            )
            .font(.recourse(12.5))
            .foregroundStyle(RecourseColor.nightMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 26)
        .padding(.trailing, 24)
    }

    private var requestBar: some View {
        VStack(spacing: 8) {
            Button {
                environment.router.push(.newInvoice)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.down.left")
                    Text("Request money")
                }
                .font(.recourse(16, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)

            Text("Free to send. You only pay gas when you collect.")
                .font(.recourse(10.5, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 6)
        .recourseBottomFade()
    }

    // MARK: Copy

    private func glyph(for entry: InvoiceEntry) -> String {
        switch entry.standing {
        case .open: side == .owed ? "hourglass" : "exclamationmark.circle.fill"
        case .signed: side == .owed ? "arrow.down.circle.fill" : "checkmark.circle"
        case .collected: "checkmark.circle.fill"
        case .overdue: "clock.badge.xmark.fill"
        case .lapsed: "clock.badge.xmark.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private func ink(for entry: InvoiceEntry) -> Color {
        switch entry.standing {
        case .signed: side == .owed ? RecourseColor.ledger : RecourseColor.nightText
        case .collected: RecourseColor.ledger
        case .open: RecourseColor.nightText
        case .overdue, .lapsed, .cancelled: RecourseColor.nightMuted
        }
    }

    private func standingText(_ entry: InvoiceEntry) -> String {
        switch entry.standing {
        case .open:
            return "Due \(Self.relative.localizedString(for: entry.stored.dueAt, relativeTo: Date()))"
        case .signed: return side == .owed ? "Ready to collect" : "Signed"
        case .collected: return side == .owed ? "Collected" : "Paid"
        case .overdue: return "Not answered"
        case .lapsed: return "Expired unclaimed"
        case .cancelled: return "Withdrawn"
        }
    }

    /// On the owed side the counterparty is who must pay; on the owing side, who asked.
    private func name(for entry: InvoiceEntry) -> String {
        let counterparty = side == .owed ? entry.stored.payer : entry.stored.issuer
        if let handle = names[counterparty.lowercased()] { return "@\(handle)" }
        return EthereumAddress(trusted: counterparty).shortened
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private func reload(force: Bool) async {
        await book.refresh(force: force)
        await environment.chequeBook.refresh(force: force)
        await resolveNames()
    }

    private func resolveNames() async {
        let addresses = book.issued.map(\.stored.payer) + book.received.map(\.stored.issuer)
        guard !addresses.isEmpty else { return }
        if let found = try? await environment.makeHandleAPIClient().names(for: addresses) {
            names = found
        }
    }
}
