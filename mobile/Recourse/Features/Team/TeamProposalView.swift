import SwiftUI
import UIKit

/// One proposal, read in full before anything is signed.
///
/// The intent is what people approve; the hash is what the chain checks. The screen
/// shows both, recomputes the hash from the typed data on the phone, and offers no
/// signature while the two disagree. The actions are the four a member can take,
/// and only the ones the proposal's state allows are on screen.
struct TeamProposalView: View {
    let environment: AppEnvironment
    let account: String
    let txHash: String

    @State private var working: Action?
    @State private var problem: String?
    @State private var computedHash: String?
    @State private var hashCheckFailed = false
    @State private var copied = false
    @State private var vetoTransaction: ChainHash?

    private var store: TeamStore { environment.teamStore }
    private var proposal: OlienProposal? { store.proposal(account: account, txHash: txHash) }
    private var olien: OlienAccount? { store.account(account) }

    private enum Action: Equatable {
        case approve
        case execute
        case executeScheduled
        case veto
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let proposal {
                    headline(proposal)
                    calls(proposal)
                    if !proposal.hardRules.isEmpty {
                        rules(proposal)
                    }
                    if proposal.status == .scheduled {
                        schedule(proposal)
                    }
                    approvals(proposal)
                    hash(proposal)
                    if let vetoTransaction {
                        note("Your veto is on Arc as \(vetoTransaction.shortened). The queue updates within a minute.")
                    }
                    if let problem {
                        refusal(problem)
                    }
                } else {
                    HStack(spacing: 12) {
                        ProgressView().tint(RecourseColor.nightText)
                        Text("Loading the proposal")
                            .font(.recourse(13, .semibold))
                            .foregroundStyle(RecourseColor.nightText)
                    }
                    .padding(.top, 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(RecourseColor.night)
        .navigationTitle(proposal?.kindWord ?? "Proposal")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let proposal, let olien {
                actionBar(proposal, in: olien)
            }
        }
        .task {
            while !Task.isCancelled {
                await store.refreshAccount(account)
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .task(id: proposal?.typedData) {
            checkHash()
        }
    }

    // MARK: Sections

    private func headline(_ proposal: OlienProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TeamStatusPill(status: proposal.status)
                Text(proposal.approvalsText + " approved")
                    .font(.recourse(11, .semibold))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            Text(proposal.intentLine)
                .font(.recourse(24, .bold))
                .foregroundStyle(RecourseColor.nightText)
                .fixedSize(horizontal: false, vertical: true)
            if let memo = proposal.memo {
                Text(memo)
                    .font(.recourse(13))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(proposedLine(proposal))
                .font(.recourse(11.5, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
        }
        .padding(.top, 8)
    }

    private func proposedLine(_ proposal: OlienProposal) -> String {
        let when = proposal.createdDate.formatted(date: .abbreviated, time: .shortened)
        if let proposer = proposal.proposer, !proposer.name.isEmpty {
            return "Proposed by \(proposer.name), \(when)"
        }
        return "Proposed \(when)"
    }

    private func calls(_ proposal: OlienProposal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TeamSectionTitle("What it does", detail: proposal.calls.count == 1 ? "1 call" : "\(proposal.calls.count) calls")
            ForEach(Array(proposal.decoded.enumerated()), id: \.offset) { index, call in
                HStack(alignment: .top, spacing: 12) {
                    Text(call.label)
                        .font(.recourse(12, .semibold))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .frame(width: 64, alignment: .leading)
                    Text(call.summary)
                        .font(call.readable ? .recourse(13, .medium) : .system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.nightText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 10)
                if index < proposal.decoded.count - 1 {
                    Divider().overlay(RecourseColor.nightLine)
                }
            }
            if proposal.decoded.isEmpty {
                Text("The service could not describe these calls.")
                    .font(.recourse(12.5, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .padding(.vertical, 8)
            }
            if let simulation = proposal.simulation, !simulation.ok {
                note("Simulation failed: \(simulation.error ?? "the account would revert").")
                    .padding(.top, 6)
            }
        }
    }

    private func rules(_ proposal: OlienProposal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TeamSectionTitle("The account's rules", detail: nil)
            ForEach(Array(proposal.hardRules.enumerated()), id: \.offset) { _, rule in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: rule.rule == "delay" ? "clock.fill" : "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                        .frame(width: 16)
                        .padding(.top, 2)
                    Text(rule.text)
                        .font(.recourse(12.5, .medium))
                        .foregroundStyle(RecourseColor.nightText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func schedule(_ proposal: OlienProposal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TeamSectionTitle("Scheduled", detail: nil)
            if let ready = proposal.scheduledReadyDate {
                term("Can run from", ready.formatted(date: .abbreviated, time: .shortened))
                termDivider
            }
            if let ends = proposal.scheduledWindowEndsDate {
                term("Window closes", ends.formatted(date: .abbreviated, time: .shortened))
                termDivider
            }
            term(
                "Vetoes",
                "\(proposal.vetoes.count) of \(proposal.effectiveVetoThreshold) needed to stop it"
            )
            ForEach(proposal.vetoes) { veto in
                termDivider
                term("Vetoed by", veto.label)
            }
        }
    }

    private func approvals(_ proposal: OlienProposal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TeamSectionTitle("Approvals", detail: proposal.approvalsText)
            ForEach(proposal.confirmations) { confirmation in
                signerRow(
                    name: confirmation.label,
                    detail: confirmation.kind == "onchain"
                        ? "Approved on chain"
                        : "Signed \(confirmation.signedDate.formatted(date: .abbreviated, time: .shortened))",
                    mine: confirmation.signerId.lowercased() == store.mySignerID,
                    done: true
                )
                Divider().overlay(RecourseColor.nightLine).padding(.leading, 34)
            }
            ForEach(proposal.missing) { missing in
                signerRow(
                    name: missing.label,
                    detail: "Waiting",
                    mine: missing.signerId.lowercased() == store.mySignerID,
                    done: false
                )
                if missing.id != proposal.missing.last?.id {
                    Divider().overlay(RecourseColor.nightLine).padding(.leading, 34)
                }
            }
        }
    }

    private func signerRow(name: String, detail: String, mine: Bool, done: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(done ? RecourseColor.ledger : RecourseColor.nightMuted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.recourse(13.5, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                    if mine {
                        Text("You")
                            .font(.recourse(10, .bold))
                            .foregroundStyle(RecourseColor.ledger)
                    }
                }
                Text(detail)
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            Spacer()
        }
        .padding(.vertical, 9)
    }

    /// The hash the chain will check, shown whole so it can be compared with
    /// anything else that shows it, and checked here against the data.
    private func hash(_ proposal: OlienProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TeamSectionTitle("Transaction hash", detail: nil)
            Button {
                UIPasteboard.general.string = proposal.txHash
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(proposal.txHash.lowercased())
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.nightText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(copied ? RecourseColor.ledger : RecourseColor.nightMuted)
                        .frame(width: 30, height: 30)
                        .background(RecourseColor.nightChip, in: Circle())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy the transaction hash")

            if hashCheckFailed {
                note("This phone could not read the proposal's data, so the hash could not be checked. Approving is off.")
            } else if let computedHash, computedHash != proposal.txHash.lowercased() {
                VStack(alignment: .leading, spacing: 6) {
                    note("The data does not hash to this. This phone computed:")
                    Text(computedHash)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.nightText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if computedHash != nil {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Recomputed from the data on this phone")
                        .font(.recourse(11, .medium))
                }
                .foregroundStyle(RecourseColor.ledger)
            }
        }
    }

    private func term(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.recourse(12.5, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
            Spacer(minLength: 14)
            Text(value)
                .font(.recourse(13, .semibold))
                .foregroundStyle(RecourseColor.nightText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }

    private var termDivider: some View {
        Divider().overlay(RecourseColor.nightLine)
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RecourseColor.nightMuted)
                .frame(width: 16)
            Text(text)
                .font(.recourse(12, .medium))
                .foregroundStyle(RecourseColor.nightText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refusal(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .frame(width: 16)
            Text(text)
                .font(.recourse(12, .medium))
                .foregroundStyle(RecourseColor.nightText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    private var hashMatches: Bool {
        guard let proposal, let computedHash, !hashCheckFailed else { return false }
        return computedHash == proposal.txHash.lowercased()
    }

    @ViewBuilder
    private func actionBar(_ proposal: OlienProposal, in olien: OlienAccount) -> some View {
        let showsApprove = store.canApprove(proposal, in: olien) || (proposal.status == .open && store.hasConfirmed(proposal))
        let showsExecute = proposal.status == .ready
        let showsExecuteScheduled = store.canExecuteScheduled(proposal)
        let showsVeto = store.canVeto(proposal, in: olien)
        if showsApprove || showsExecute || showsExecuteScheduled || showsVeto {
            VStack(spacing: 9) {
                if showsApprove {
                    primary(
                        title: store.hasConfirmed(proposal) ? "You approved this" : "Approve with Face ID",
                        working: "Signing…",
                        action: .approve,
                        enabled: store.canApprove(proposal, in: olien) && hashMatches
                    )
                }
                if showsExecute {
                    primary(title: "Execute", working: "Executing on Arc…", action: .execute, enabled: true)
                }
                if showsExecuteScheduled {
                    primary(title: "Execute now", working: "Executing on Arc…", action: .executeScheduled, enabled: true)
                }
                if showsVeto {
                    secondary(title: "Veto this change", working: "Sending your veto…", action: .veto)
                }
                Text(footnote(proposal, showsVeto: showsVeto, showsApprove: showsApprove))
                    .font(.recourse(10.5, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 6)
            .recourseBottomFade()
        }
    }

    private func footnote(_ proposal: OlienProposal, showsVeto: Bool, showsApprove: Bool) -> String {
        if showsVeto {
            return "A veto is a transaction from your account. It costs a little gas, paid in USDC from your balance."
        }
        if proposal.status == .ready {
            return "Anyone can execute a ready proposal. The treasury pays its own gas."
        }
        if showsApprove {
            return "Your approval is a signature. Nothing moves until \(proposal.required) have signed and someone executes."
        }
        return "Past its delay. Executing runs the change the treasury already agreed to."
    }

    private func primary(title: String, working workingTitle: String, action: Action, enabled: Bool) -> some View {
        Button {
            perform(action)
        } label: {
            HStack(spacing: 10) {
                if working == action { ProgressView().tint(.white) }
                Text(working == action ? workingTitle : title)
            }
            .font(.recourse(16, .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(RecourseColor.ledger, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || working != nil)
        .opacity(!enabled || working != nil ? 0.55 : 1)
    }

    private func secondary(title: String, working workingTitle: String, action: Action) -> some View {
        Button {
            perform(action)
        } label: {
            HStack(spacing: 10) {
                if working == action { ProgressView().tint(RecourseColor.nightText) }
                Text(working == action ? workingTitle : title)
            }
            .font(.recourse(16, .semibold))
            .foregroundStyle(RecourseColor.nightText)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                Capsule().stroke(RecourseColor.nightLine, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(working != nil)
        .opacity(working != nil ? 0.55 : 1)
    }

    private func perform(_ action: Action) {
        guard working == nil, let proposal else { return }
        working = action
        problem = nil

        Task {
            do {
                switch action {
                case .approve:
                    _ = try await store.approve(proposal)
                case .execute:
                    _ = try await store.execute(proposal)
                case .executeScheduled:
                    _ = try await store.executeScheduled(proposal)
                case .veto:
                    vetoTransaction = try await store.veto(proposal)
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                problem = message(for: error)
            }
            working = nil
        }
    }

    private func checkHash() {
        guard let proposal else { return }
        do {
            computedHash = try OlienSigning.transactionHash(typedData: proposal.typedDataJSON()).value.lowercased()
            hashCheckFailed = false
        } catch {
            computedHash = nil
            hashCheckFailed = true
        }
    }

    private func message(for error: any Error) -> String {
        switch error {
        case let error as TeamError:
            if case .hashMismatch(let expected, let computed) = error {
                return "The data hashes to \(computed), not \(expected). Nothing was signed."
            }
            return error.message
        case let error as OlienAPIError:
            return error.message
        case AccountSessionError.signedOut:
            return "Sign in again to act for this team."
        case SafeSubmitError.operationFailed:
            return "Arc rejected the veto. The change was not stopped and the gas was spent."
        case SafeSubmitError.operationTimedOut:
            return "The veto was sent but Arc has not confirmed it yet. Check the queue in a minute."
        case BundlerError.rejected(let reason):
            return "The bundler refused the veto: \(reason)"
        case is DeviceKeyError:
            return "This phone could not sign with its device key."
        case BuyerSignerError.signingFailed:
            return "The Cloud Key could not sign. Try again."
        default:
            return "That could not be completed. Please try again."
        }
    }
}
