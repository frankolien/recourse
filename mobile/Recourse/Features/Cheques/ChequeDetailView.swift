import SwiftUI
import UIKit

/// One cheque, and the single thing you can do with it.
///
/// Cashing and voiding are the only two actions, and which one you get is decided by
/// who you are rather than offered as a choice: the holder cashes, the writer voids.
/// Anything settled offers neither, and says why in a sentence instead of leaving a
/// dead button on screen.
struct ChequeDetailView: View {
    let entry: ChequeEntry
    let counterpartyName: String
    /// True when the signed-in account wrote this one.
    let mine: Bool
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var problem: String?
    @State private var settled: Settlement?

    private struct Settlement: Identifiable {
        let id = UUID()
        let cashed: Bool
        let hash: ChainHash
        let amount: USDCAmount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ChequePaper(entry: entry, counterpartyName: counterpartyName, mine: mine)
                        .padding(.top, 6)

                    terms

                    if let problem {
                        refusal(problem)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(RecourseColor.night)
            .navigationTitle(mine ? "Cheque you wrote" : "Cheque for you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
        }
        .fullScreenCover(item: $settled) { result in
            ChequeSettledView(
                cashed: result.cashed,
                amount: result.amount,
                hash: result.hash,
                counterpartyName: counterpartyName
            ) {
                settled = nil
                dismiss()
            }
        }
    }

    // MARK: Sections

    private var terms: some View {
        VStack(alignment: .leading, spacing: 0) {
            term("Amount", entry.stored.usdc.formatted)
            termDivider
            term(mine ? "Written to" : "Written by", counterpartyName)
            termDivider
            term("Expires", entry.stored.expiresAt.formatted(date: .abbreviated, time: .shortened))
            termDivider
            // The nonce is what a cheque is uniquely identified by on chain, and the
            // only handle anyone has for it if something needs checking by hand.
            term("Reference", String(entry.stored.nonce.suffix(10)), monospaced: true)
        }
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

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 9) {
            if let action = availableAction {
                Button {
                    perform(action)
                } label: {
                    HStack(spacing: 10) {
                        if working { ProgressView().tint(action == .cash ? .white : RecourseColor.nightText) }
                        Text(working ? workingTitle(action) : title(action))
                    }
                    .font(.recourse(16, .semibold))
                    .foregroundStyle(action == .cash ? .white : RecourseColor.nightText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if action == .cash {
                            Capsule().fill(RecourseColor.ledger)
                        } else {
                            Capsule().stroke(RecourseColor.nightLine, lineWidth: 1)
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

    // MARK: Actions

    private enum Action: Equatable { case cash, void }

    private var availableAction: Action? {
        guard entry.standing == .cashable else { return nil }
        return mine ? .void : .cash
    }

    private func title(_ action: Action) -> String {
        switch action {
        case .cash: "Cash \(entry.stored.usdc.decimalString) USDC"
        case .void: "Void this cheque"
        }
    }

    private func workingTitle(_ action: Action) -> String {
        action == .cash ? "Cashing on Arc…" : "Voiding on Arc…"
    }

    private var footnote: String {
        switch entry.standing {
        case .cashable:
            return mine
                ? "Voiding burns the cheque on Arc so it can never be cashed. Costs gas."
                : "You submit it, so you pay the gas. In USDC, on Arc."
        case .notYet(let from):
            return "Cashable from \(from.formatted(date: .abbreviated, time: .shortened))."
        case .expired:
            return "This cheque expired and can no longer be cashed. The amount stayed where it was."
        case .cashed:
            return mine
                ? "Cashed. The money left your wallet when they submitted it."
                : "You cashed this one. The money is in your wallet."
        case .voided:
            return "Voided on chain. The signature is worthless now."
        }
    }

    private func perform(_ action: Action) {
        guard !working else { return }
        working = true
        problem = nil

        Task {
            do {
                let workflow = try environment.makeChequeWorkflow()
                let hash: ChainHash
                switch action {
                case .cash:
                    hash = try await workflow.cash(entry.stored)
                case .void:
                    hash = try await workflow.void(entry.stored)
                    environment.chequeBook.rememberVoided(nonce: entry.stored.nonce)
                }
                await environment.chequeBook.refresh(force: true)
                await environment.paymentStore.refreshBuyer()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                settled = Settlement(cashed: action == .cash, hash: hash, amount: entry.stored.usdc)
            } catch {
                problem = message(for: error)
            }
            working = false
        }
    }

    private func message(for error: any Error) -> String {
        switch error {
        case ChequeError.alreadySettled:
            mine
                ? "Too late: this cheque has already been cashed."
                : "This cheque has already been used. Nothing was submitted and you paid no gas."
        case ChequeError.expiryInThePast:
            "This cheque expired before it was cashed."
        case ChequeError.notYours:
            "This cheque is not addressed to this wallet."
        case ChequeError.transactionReverted:
            "Arc rejected the transaction. Nothing moved."
        case TransactionAuthorizationError.cancelled:
            "Cancelled."
        case TransactionAuthorizationError.unavailable:
            "Set a device passcode or Face ID first."
        case ContractReadError.rpc(let code, let message):
            "Arc RPC error \(code): \(message)"
        default:
            "That could not be completed. Please try again."
        }
    }
}

/// What happened, stated once and plainly.
private struct ChequeSettledView: View {
    let cashed: Bool
    let amount: USDCAmount
    let hash: ChainHash
    let counterpartyName: String
    let onDone: () -> Void

    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: cashed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(cashed ? RecourseColor.ledger : RecourseColor.nightMuted)
                    .scaleEffect(revealed ? 1 : 0.6)

                Text(cashed ? "Cashed" : "Voided")
                    .font(.recourse(28, .bold))
                    .foregroundStyle(RecourseColor.nightText)

                Text(amount.formatted)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(RecourseColor.nightText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(
                    cashed
                        ? "From \(counterpartyName), now in your wallet."
                        : "That cheque can never be cashed. Its nonce is burned on Arc."
                )
                .font(.recourse(12.5, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                Text(hash.shortened)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(RecourseColor.nightMuted)
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
}
