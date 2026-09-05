import SwiftUI

/// One treasury: what it holds, who can move it, and what is waiting.
///
/// The queue is grouped by whether anything can still happen to it. Active needs
/// people; Scheduled needs time, and can be stopped; Done is the record.
struct TeamAccountView: View {
    let environment: AppEnvironment
    let address: String

    private var store: TeamStore { environment.teamStore }
    private var account: OlienAccount? { store.account(address) }
    private var summary: OlienSummary? { store.summary(address) }
    private var queue: [OlienProposal] { store.proposals(for: address) }

    private var name: String {
        account?.displayName ?? summary?.displayName ?? "\(address.prefix(6))…\(address.suffix(4))"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                header
                if let account {
                    members(account)
                }
                queueSections
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.recourse(12, .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(RecourseColor.night)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.refreshAccount(address)
        }
        .task {
            while !Task.isCancelled {
                await store.refreshAccount(address)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BALANCE")
                .font(.recourse(10, .semibold))
                .kerning(1.1)
                .foregroundStyle(RecourseColor.nightMuted)
            Text((account?.usdc ?? summary?.usdc)?.decimalString ?? "…")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(RecourseColor.nightText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                Text("USDC on Arc")
                if let account {
                    Text("·")
                    Text("\(account.threshold) of \(account.signers.count) to approve")
                } else if let summary {
                    Text("·")
                    Text("\(summary.threshold) of \(summary.signerCount) to approve")
                }
            }
            .font(.recourse(12, .medium))
            .foregroundStyle(RecourseColor.nightMuted)
            Text(address.lowercased())
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(RecourseColor.nightMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 2)
        }
        .padding(.top, 10)
    }

    // MARK: Members

    private func members(_ account: OlienAccount) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TeamSectionTitle("Members", detail: account.signers.count == 1 ? "1 signer" : "\(account.signers.count) signers")
            ForEach(account.signers) { signer in
                memberRow(signer, mine: signer.signerId.lowercased() == store.mySignerID)
                if signer.id != account.signers.last?.id {
                    Divider().overlay(RecourseColor.nightLine).padding(.leading, 50)
                }
            }
        }
    }

    private func memberRow(_ signer: OlienSigner, mine: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: glyph(for: signer))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(mine ? RecourseColor.ledger : RecourseColor.nightText)
                .frame(width: 38, height: 38)
                .background(RecourseColor.nightChip, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(signer.displayName)
                        .font(.recourse(14, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                        .lineLimit(1)
                    if mine {
                        Text("You")
                            .font(.recourse(10, .bold))
                            .foregroundStyle(RecourseColor.ledger)
                    }
                }
                Text(permissionsLine(signer))
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(signer.kindWord)
                .font(.recourse(11, .semibold))
                .foregroundStyle(RecourseColor.nightMuted)
        }
        .padding(.vertical, 10)
    }

    private func glyph(for signer: OlienSigner) -> String {
        switch signer.kind {
        case "webauthn": "person.badge.key.fill"
        case "p256": "faceid"
        case "contract": "person.crop.circle.fill"
        default: "wallet.pass.fill"
        }
    }

    private func permissionsLine(_ signer: OlienSigner) -> String {
        var words: [String] = []
        if signer.canApprove { words.append("Approves") }
        if signer.canVeto { words.append("vetoes") }
        if signer.permissions.contains("recover") { words.append("recovers") }
        guard !words.isEmpty else { return "No powers" }
        let line = words.joined(separator: ", ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }

    // MARK: Queue

    private var active: [OlienProposal] { queue.filter { $0.status.isActive } }
    private var scheduled: [OlienProposal] { queue.filter { $0.status == .scheduled } }
    private var done: [OlienProposal] { queue.filter { !$0.status.isActive && $0.status != .scheduled } }

    @ViewBuilder
    private var queueSections: some View {
        if queue.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                TeamSectionTitle("Queue", detail: nil)
                Text("Nothing proposed yet.")
                    .font(.recourse(13, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .padding(.top, 6)
            }
        } else {
            if !active.isEmpty { group("Active", active) }
            if !scheduled.isEmpty { group("Scheduled", scheduled) }
            if !done.isEmpty { group("Done", done) }
        }
    }

    private func group(_ title: String, _ proposals: [OlienProposal]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TeamSectionTitle(title, detail: proposals.count == 1 ? "1 proposal" : "\(proposals.count) proposals")
            ForEach(proposals) { proposal in
                Button {
                    environment.router.push(.teamProposal(account: address, txHash: proposal.txHash))
                } label: {
                    proposalRow(proposal)
                }
                .buttonStyle(.plain)
                if proposal.id != proposals.last?.id {
                    Divider().overlay(RecourseColor.nightLine)
                }
            }
        }
    }

    private func proposalRow(_ proposal: OlienProposal) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(proposal.intentLine)
                    .font(.recourse(14, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle(proposal))
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                TeamStatusPill(status: proposal.status)
                Text(proposal.approvalsText)
                    .font(.recourse(11, .semibold))
                    .foregroundStyle(waitingOnMe(proposal) ? RecourseColor.ledger : RecourseColor.nightMuted)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func waitingOnMe(_ proposal: OlienProposal) -> Bool {
        guard let mine = store.mySignerID else { return false }
        return proposal.status == .open && proposal.isMissing(mine)
    }

    private func subtitle(_ proposal: OlienProposal) -> String {
        if waitingOnMe(proposal) { return "Waiting for you" }
        if let memo = proposal.memo { return memo }
        if proposal.status == .scheduled, let ready = proposal.scheduledReadyDate {
            return "Ready \(Self.relative.localizedString(for: ready, relativeTo: Date()))"
        }
        if let first = proposal.missing.first, proposal.status == .open {
            return "Waiting for \(first.label)"
        }
        return proposal.createdDate.formatted(date: .abbreviated, time: .shortened)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

/// An eyebrow with an optional count, the way every list on the in-app theme is
/// headed: text on the ground, no container.
struct TeamSectionTitle: View {
    let title: String
    let detail: String?

    init(_ title: String, detail: String?) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.recourse(10, .semibold))
                .kerning(1.1)
                .foregroundStyle(RecourseColor.nightMuted)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.recourse(10.5, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
        }
        .padding(.bottom, 6)
    }
}

/// A status word in an outline. Not a chip: nothing about it is tappable, so it
/// carries no fill.
struct TeamStatusPill: View {
    let status: OlienProposalStatus

    var body: some View {
        Text(status.word)
            .font(.recourse(10, .bold))
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay {
                Capsule().stroke(ink.opacity(0.55), lineWidth: 1)
            }
    }

    private var ink: Color {
        switch status {
        case .open, .ready, .executing, .scheduled: RecourseColor.ledger
        case .executed: RecourseColor.nightText
        case .blocked, .vetoed, .cancelled, .replaced, .stale, .expired, .failed, .unknown: RecourseColor.nightMuted
        }
    }
}
