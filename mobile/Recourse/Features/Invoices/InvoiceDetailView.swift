import SwiftUI
import UIKit

/// One invoice, rendered as a statement.
///
/// A cheque is drawn as an object because it is one: something handed over. An invoice
/// is a document, so it is set as one, ruled and right aligned to a total. The
/// difference is deliberate, so the two are never mistaken for each other at a glance.
struct InvoiceDetailView: View {
    let entry: InvoiceEntry
    let counterpartyName: String
    /// True when this account issued it, which decides whether you collect or pay.
    let mine: Bool
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var problem: String?
    @State private var done: Outcome?

    private struct Outcome: Identifiable {
        let id = UUID()
        let kind: InvoiceOutcomeKind
        let amount: USDCAmount
        let hash: ChainHash?
    }

    private var stored: StoredInvoice { entry.stored }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    statement
                    if let problem {
                        refusal(problem)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(RecourseColor.night)
            .navigationTitle(mine ? "You invoiced" : "Invoice for you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
        }
        .fullScreenCover(item: $done) { outcome in
            InvoiceOutcomeView(
                kind: outcome.kind,
                amount: outcome.amount,
                hash: outcome.hash,
                counterpartyName: counterpartyName
            ) {
                done = nil
                dismiss()
            }
        }
    }

    // MARK: The statement

    private var statement: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mine ? "BILLED TO" : "FROM")
                        .font(.recourse(9, .semibold))
                        .kerning(1.3)
                        .foregroundStyle(RecourseColor.nightMuted)
                    Text(counterpartyName)
                        .font(.recourse(20, .bold))
                        .foregroundStyle(RecourseColor.nightText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                standingBadge
            }
            .padding(.bottom, 22)

            // The line item, set the way a bill sets one: description left, amount
            // right, ruled above the total.
            Text("DESCRIPTION")
                .font(.recourse(9, .semibold))
                .kerning(1.3)
                .foregroundStyle(RecourseColor.nightMuted)
                .padding(.bottom, 7)
            Text(stored.memo)
                .font(.recourse(14, .medium))
                .foregroundStyle(RecourseColor.nightText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            Rectangle()
                .fill(RecourseColor.nightLine)
                .frame(height: 1)
                .padding(.bottom, 16)

            HStack(alignment: .lastTextBaseline) {
                Text(entry.standing == .collected ? "PAID" : "AMOUNT DUE")
                    .font(.recourse(10, .semibold))
                    .kerning(1.2)
                    .foregroundStyle(RecourseColor.nightMuted)
                Spacer()
                Text(stored.usdc.decimalString)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(RecourseColor.nightText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("USDC")
                    .font(.recourse(12, .bold))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            .padding(.bottom, 22)

            VStack(spacing: 0) {
                term(entry.standing == .collected ? "Collected" : "Due", dueText)
                termDivider
                term("Issued", stored.createdAt.prefix(10).description)
                if stored.isSigned {
                    termDivider
                    term("Signed", signedText)
                }
                termDivider
                // The nonce is the invoice's identity on chain, and the only handle
                // anyone has if something needs checking by hand.
                term("Reference", String(stored.nonce.suffix(10)), monospaced: true)
            }
        }
    }

    private var standingBadge: some View {
        Text(badgeText)
            .font(.recourse(10, .semibold))
            .kerning(0.4)
            .foregroundStyle(badgeInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(badgeInk.opacity(0.12), in: Capsule())
    }

    private func term(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.recourse(12.5, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
            Spacer(minLength: 14)
            Text(value)
                .font(
                    monospaced
                        ? .system(size: 12, weight: .medium, design: .monospaced)
                        : .recourse(13, .semibold)
                )
                .foregroundStyle(RecourseColor.nightText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 13)
    }

    private var termDivider: some View {
        Divider().overlay(RecourseColor.nightLine)
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

    private enum Action: Equatable { case pay, collect, withdraw }

    /// One action, chosen by who you are and where the invoice stands. Never a menu:
    /// at any moment there is exactly one thing to do, or nothing.
    private var availableAction: Action? {
        switch entry.standing {
        case .open: mine ? .withdraw : .pay
        case .signed: mine ? .collect : nil
        case .overdue, .lapsed, .collected, .cancelled: nil
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 9) {
            if let action = availableAction {
                Button {
                    perform(action)
                } label: {
                    HStack(spacing: 10) {
                        if working { ProgressView().tint(action == .withdraw ? RecourseColor.nightText : .white) }
                        Text(working ? workingTitle(action) : title(action))
                    }
                    .font(.recourse(16, .semibold))
                    .foregroundStyle(action == .withdraw ? RecourseColor.nightText : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if action == .withdraw {
                            Capsule().stroke(RecourseColor.nightLine, lineWidth: 1)
                        } else {
                            Capsule().fill(RecourseColor.ledger)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(working)
                .opacity(working ? 0.7 : 1)
            }

            Text(footnote)
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

    private func title(_ action: Action) -> String {
        switch action {
        case .pay: "Pay \(stored.usdc.decimalString) USDC"
        case .collect: "Collect \(stored.usdc.decimalString) USDC"
        case .withdraw: "Withdraw this invoice"
        }
    }

    private func workingTitle(_ action: Action) -> String {
        switch action {
        case .pay: "Signing…"
        case .collect: "Collecting on Arc…"
        case .withdraw: "Withdrawing…"
        }
    }

    private var footnote: String {
        switch entry.standing {
        case .open:
            return mine
                ? "You can withdraw it while it is unanswered. Once they sign, only they can undo it."
                : "Paying is a signature, not a transfer. It costs you no gas, and they collect when they choose."
        case .signed:
            return mine
                ? "They have signed. Collecting submits it on Arc and you pay the gas, in USDC."
                : "You have signed this. The money leaves your wallet when they collect it."
        case .collected:
            return mine ? "Collected. The money is in your wallet." : "Paid. This is settled."
        case .overdue:
            return "Nobody answered before the due date, so it can no longer be paid."
        case .lapsed:
            return mine
                ? "They signed, but you did not collect before it expired. The money stayed with them."
                : "You signed this and it was never collected. Nothing left your wallet."
        case .cancelled:
            return "Withdrawn by the issuer. Nothing was owed."
        }
    }

    private func perform(_ action: Action) {
        guard !working else { return }
        working = true
        problem = nil

        Task {
            do {
                let workflow = try environment.makeInvoiceWorkflow()
                switch action {
                case .pay:
                    let committed = environment.chequeBook.committed
                    _ = try await environment.accountSession.withAccessToken { token in
                        try await workflow.pay(stored, committed: committed, accessToken: token)
                    }
                    done = Outcome(kind: .paid, amount: stored.usdc, hash: nil)
                case .collect:
                    let hash = try await workflow.collect(stored)
                    done = Outcome(kind: .collected, amount: stored.usdc, hash: hash)
                case .withdraw:
                    _ = try await environment.accountSession.withAccessToken { token in
                        try await workflow.cancel(stored, accessToken: token)
                    }
                    done = Outcome(kind: .withdrawn, amount: stored.usdc, hash: nil)
                }
                await environment.invoiceBook.refresh(force: true)
                await environment.paymentStore.refreshBuyer()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                problem = message(for: error)
            }
            working = false
        }
    }

    private func message(for error: any Error) -> String {
        switch error {
        case InvoiceError.alreadyAnswered:
            mine
                ? "This invoice has already been collected."
                : "This invoice has already been answered."
        case InvoiceError.expired:
            "This invoice is past its due date."
        case InvoiceError.notYours:
            "This invoice is not addressed to this wallet."
        case InvoiceError.overcommitted(let available):
            "You can commit up to \(available.formatted) right now. The rest of your balance is promised to cheques you have written."
        case InvoiceError.notSigned:
            "Nobody has signed this yet, so there is nothing to collect."
        case InvoiceError.transactionReverted:
            "Arc rejected the transaction. Nothing moved."
        case TransactionAuthorizationError.cancelled:
            "Cancelled."
        case TransactionAuthorizationError.unavailable:
            "Set a device passcode or Face ID first."
        case is InvoiceAPIError:
            (error as? InvoiceAPIError)?.message ?? "That could not be completed."
        default:
            "That could not be completed. Please try again."
        }
    }

    // MARK: Copy

    private var badgeText: String {
        switch entry.standing {
        case .open: mine ? "Awaiting them" : "Awaiting you"
        case .signed: mine ? "Ready to collect" : "Signed"
        case .collected: mine ? "Collected" : "Paid"
        case .overdue: "Not answered"
        case .lapsed: "Expired"
        case .cancelled: "Withdrawn"
        }
    }

    private var badgeInk: Color {
        switch entry.standing {
        case .signed, .collected: RecourseColor.ledger
        case .open: RecourseColor.nightText
        case .overdue, .lapsed, .cancelled: RecourseColor.nightMuted
        }
    }

    private var dueText: String {
        stored.dueAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var signedText: String {
        guard let signedAt = stored.signedAt else { return "Yes" }
        return signedAt.prefix(10).description
    }
}

private enum InvoiceOutcomeKind { case paid, collected, withdrawn }

/// What happened, said once.
private struct InvoiceOutcomeView: View {
    let kind: InvoiceOutcomeKind
    let amount: USDCAmount
    let hash: ChainHash?
    let counterpartyName: String
    let onDone: () -> Void

    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: glyph)
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(kind == .withdrawn ? RecourseColor.nightMuted : RecourseColor.ledger)
                    .scaleEffect(revealed ? 1 : 0.6)

                Text(headline)
                    .font(.recourse(28, .bold))
                    .foregroundStyle(RecourseColor.nightText)

                Text(amount.formatted)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(RecourseColor.nightText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(detail)
                    .font(.recourse(12.5, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let hash {
                    Text(hash.shortened)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }
            .offset(y: revealed ? 0 : 14)
            .opacity(revealed ? 1 : 0)
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(RecoursePrimaryButtonStyle())
        }
        .padding(24)
        .background(RecourseColor.night.ignoresSafeArea())
        .task {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { revealed = true }
        }
    }

    private var glyph: String {
        switch kind {
        case .paid: "signature"
        case .collected: "checkmark.seal.fill"
        case .withdrawn: "xmark.seal.fill"
        }
    }

    private var headline: String {
        switch kind {
        case .paid: "Signed"
        case .collected: "Collected"
        case .withdrawn: "Withdrawn"
        }
    }

    private var detail: String {
        switch kind {
        // Careful wording: signing an invoice does not move money, and telling someone
        // they have paid when their balance has not changed is the kind of lie they
        // find out about later.
        case .paid: "\(counterpartyName) can collect this whenever they like. It leaves your balance then, not now."
        case .collected: "From \(counterpartyName), now in your wallet."
        case .withdrawn: "\(counterpartyName) will not see it any more. Nothing was owed."
        }
    }
}
