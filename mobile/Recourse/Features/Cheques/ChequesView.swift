import SwiftUI

/// The cheque book: what is waiting for you, and what you have promised away.
///
/// Two lists rather than one, because they answer opposite questions. Received asks
/// "what can I take"; Written asks "what do I still owe", and that second number is the
/// one this app is unusual for showing at all. Nothing on chain reserves the balance
/// behind a cheque, so if the app did not keep the running total, nobody would.
struct ChequesView: View {
    let environment: AppEnvironment

    private enum Side: String, CaseIterable, Identifiable {
        case received
        case written

        var id: String { rawValue }
        var title: String {
            switch self {
            case .received: "Received"
            case .written: "Written"
            }
        }
    }

    @State private var side: Side = .received
    @State private var names: [String: String] = [:]
    @State private var selected: ChequeEntry?

    private var book: ChequeBook { environment.chequeBook }

    private var entries: [ChequeEntry] {
        side == .received ? book.received : book.written
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
        .navigationTitle("Cheques")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await reload()
        }
        .safeAreaInset(edge: .bottom) {
            writeBar
        }
        .sheet(item: $selected) { entry in
            ChequeDetailView(
                entry: entry,
                counterpartyName: name(for: entry),
                mine: side == .written,
                environment: environment
            )
            .presentationDetents([.large])
            .presentationBackground(RecourseColor.night)
        }
        .task {
            await reload()
        }
    }

    // MARK: Sections

    /// The two numbers a cheque book is for. Cashable is money someone has already
    /// promised you; outstanding is money you have promised and cannot spend twice.
    private var summary: some View {
        HStack(alignment: .top, spacing: 0) {
            figure(
                label: "Ready to cash",
                amount: book.cashableTotal,
                detail: book.cashableCount == 1 ? "1 cheque" : "\(book.cashableCount) cheques",
                accent: book.cashableCount > 0
            )
            Rectangle()
                .fill(RecourseColor.nightLine)
                .frame(width: 1, height: 44)
                .padding(.horizontal, 18)
            figure(
                label: "You have written",
                amount: book.committed,
                detail: book.liveWrittenCount == 1 ? "1 outstanding" : "\(book.liveWrittenCount) outstanding",
                accent: false
            )
        }
        .padding(.top, 10)
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
                        Capsule()
                            .fill(RecourseColor.nightChip)
                            .matchedGeometryEffect(id: "cheque-side", in: sideNamespace)
                    }
                }
            }
        }
        .padding(4)
        .recourseGlassField(cornerRadius: 24)
    }

    @Namespace private var sideNamespace

    private func row(_ entry: ChequeEntry) -> some View {
        HStack(spacing: 13) {
            Image(systemName: glyph(for: entry))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(entry.standing.isLive ? RecourseColor.ledger : RecourseColor.nightMuted)
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
                Text(entry.stored.usdc.decimalString)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(amountInk(for: entry))
                    .strikethrough(entry.standing == .voided || entry.standing == .expired, color: RecourseColor.nightMuted)
                Text(standingText(entry))
                    .font(.recourse(10, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // A server that did not answer is not an empty book, so the empty state says
    // which one it is.
    @ViewBuilder
    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                book.errorMessage != nil
                    ? "Cheques could not be loaded"
                    : side == .received ? "No cheques written to you" : "You have not written one"
            )
            .font(.recourse(15, .semibold))
            .foregroundStyle(RecourseColor.nightText)
            Text(
                book.errorMessage != nil
                    ? "Recourse is not answering. Pull down to try again."
                    : side == .received
                        ? "When someone writes you a cheque it lands here, and cashing it is one tap. They do not need to be online for you to take the money."
                        : "A cheque is a payment the other person collects when they choose to. It costs nothing to write, expires on its own, and you can void it any time before it is cashed."
            )
            .font(.recourse(12.5))
            .foregroundStyle(RecourseColor.nightMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 26)
        .padding(.trailing, 24)
    }

    private var writeBar: some View {
        VStack(spacing: 8) {
            Button {
                environment.router.push(.writeCheque)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "square.and.pencil")
                    Text("Write a cheque")
                }
                .font(.recourse(16, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)

            if let balance = environment.paymentStore.balance {
                // The one line that keeps a writer honest. A cheque is not held by the
                // token, so the balance alone would overstate what can be promised.
                Text("\(book.available(balance: balance).decimalString) USDC free to write against")
                    .font(.recourse(10.5, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 6)
        .recourseBottomFade()
    }

    // MARK: Copy

    private func glyph(for entry: ChequeEntry) -> String {
        switch entry.standing {
        case .cashable: side == .received ? "arrow.down.circle.fill" : "clock.fill"
        case .notYet: "clock.badge.fill"
        case .expired: "clock.badge.xmark.fill"
        case .cashed: "checkmark.circle.fill"
        case .voided: "xmark.circle.fill"
        }
    }

    private func amountInk(for entry: ChequeEntry) -> Color {
        switch entry.standing {
        case .cashable: side == .received ? RecourseColor.ledger : RecourseColor.nightText
        case .cashed: RecourseColor.nightText
        case .notYet, .expired, .voided: RecourseColor.nightMuted
        }
    }

    private func standingText(_ entry: ChequeEntry) -> String {
        switch entry.standing {
        case .cashable:
            return side == .received ? "Ready" : "Outstanding"
        case .notYet(let from):
            return "From \(from.formatted(date: .abbreviated, time: .omitted))"
        case .expired: return "Expired"
        case .cashed: return "Cashed"
        case .voided: return "Voided"
        }
    }

    private func subtitle(for entry: ChequeEntry) -> String {
        if let memo = entry.stored.memo, !memo.isEmpty { return memo }
        guard entry.standing.isLive else {
            return entry.stored.expiresAt.formatted(date: .abbreviated, time: .omitted)
        }
        return "Expires \(Self.relative.localizedString(for: entry.stored.expiresAt, relativeTo: Date()))"
    }

    /// The counterparty, named if the directory knows them. On the received side that
    /// is whoever wrote it; on the written side, whoever it was written to.
    private func name(for entry: ChequeEntry) -> String {
        let counterparty = side == .received ? entry.stored.from : entry.stored.to
        if let handle = names[counterparty.lowercased()] { return "@\(handle)" }
        return EthereumAddress(trusted: counterparty).shortened
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private func reload() async {
        await book.refresh(force: true)
        await environment.paymentStore.refreshBuyer()
        await resolveNames()
    }

    /// One batched lookup for every address on screen, so a list of ten cheques is one
    /// request rather than ten.
    private func resolveNames() async {
        let addresses = (book.received.map(\.stored.from) + book.written.map(\.stored.to))
        guard !addresses.isEmpty else { return }
        if let found = try? await environment.makeHandleAPIClient().names(for: addresses) {
            names = found
        }
    }
}
