import SwiftUI
import UIKit

/// Write a cheque: an amount, a person, and how long they have to take it.
///
/// Nothing here touches the chain. The output is a signature, which is why writing one
/// is free and instant and can be done with no gas and no confirmation to wait for.
///
/// It is also why this screen leads with what is free to write rather than with the
/// balance. The token will not hold anything back for a cheque, so the balance is the
/// wrong number: someone holding 15 USDC who has already written 10 can honestly
/// promise 5, and a screen that showed 15 would be helping them write a cheque that
/// bounces.
struct WriteChequeView: View {
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var recipientText = ""
    @State private var memoText = ""
    @State private var validity: ChequeValidity = .week
    @State private var resolvedHandle: ResolvedHandle?
    @State private var resolvingHandle = false
    @State private var handleProblem: String?
    @State private var writing = false
    @State private var problem: String?
    @State private var written: StoredCheque?
    @FocusState private var focus: Field?

    private enum Field { case amount, recipient, memo }

    private var book: ChequeBook { environment.chequeBook }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                amountEntry
                recipientField
                    .padding(.top, 26)
                validityPicker
                    .padding(.top, 26)
                memoField
                    .padding(.top, 26)
                if let problem {
                    refusal(problem)
                        .padding(.top, 20)
                }
                promiseNote
                    .padding(.top, 26)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(RecourseColor.night)
        .navigationTitle("Write a cheque")
        .navigationBarTitleDisplayMode(.inline)
        .recourseKeyboardDismissal()
        .safeAreaInset(edge: .bottom) { signBar }
        .task(id: recipientText) { await resolveRecipient() }
        .task {
            await environment.paymentStore.refreshBuyer()
            await book.refresh()
        }
        .fullScreenCover(item: $written) { stored in
            ChequeWrittenView(
                stored: stored,
                counterpartyName: payeeName,
                onDone: {
                    written = nil
                    environment.router.reset()
                }
            )
        }
    }

    // MARK: Sections

    private var amountEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("Amount")

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .amount)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(RecourseColor.nightText)
                Text("USDC")
                    .font(.recourse(14, .bold))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            .padding(.horizontal, 18)
            .frame(height: 82)
            .recourseGlassField()

            availabilityLine
        }
        .recourseGlassGroup(spacing: 6)
    }

    /// What can honestly be written, and the arithmetic behind it when it differs from
    /// the balance. Silent when nothing is committed, because then there is nothing to
    /// explain.
    private var availabilityLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 10, weight: .semibold))
            Text(availabilityText)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            if available.baseUnits > 0 {
                Button {
                    amountText = available.decimalString
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text("Max")
                        .font(.recourse(11, .bold))
                        .foregroundStyle(RecourseColor.ledger)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .recourseGlassCapsule()
                .accessibilityLabel("Write for the maximum, \(available.decimalString) USDC")
            }
        }
        .font(.recourse(11, .medium))
        .foregroundStyle(RecourseColor.nightMuted)
        .padding(.top, 4)
    }

    private var availabilityText: String {
        guard environment.paymentStore.balance != nil else { return "Checking your balance" }
        let committed = book.committed
        guard committed.baseUnits > 0 else {
            return "\(available.decimalString) USDC free to write against"
        }
        return "\(available.decimalString) free · \(committed.decimalString) already promised"
    }

    private var recipientField: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("Pay to")

            HStack(spacing: 10) {
                TextField("@name or wallet address", text: $recipientText)
                    .font(
                        looksLikeAddress
                            ? .system(size: 13, weight: .medium, design: .monospaced)
                            : .recourse(16, .medium)
                    )
                    .foregroundStyle(RecourseColor.nightText)
                    .focused($focus, equals: .recipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if resolvingHandle {
                    ProgressView().controlSize(.small).tint(RecourseColor.nightMuted)
                }
                Button {
                    if let pasted = UIPasteboard.general.string {
                        recipientText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste an address")
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .recourseGlassField()

            if let resolvedHandle, recipient != nil {
                Label(
                    "@\(resolvedHandle.handle) · \(EthereumAddress(trusted: resolvedHandle.address).shortened)",
                    systemImage: "at.circle.fill"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
            } else if let handleProblem, recipient == nil {
                Text(handleProblem)
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
        }
    }

    private var validityPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("Good for")

            HStack(spacing: 8) {
                ForEach(ChequeValidity.allCases) { option in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.2)) { validity = option }
                    } label: {
                        Text(option.shortLabel)
                            .font(.recourse(13, .semibold))
                            .foregroundStyle(validity == option ? .white : RecourseColor.nightText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background {
                                if validity == option {
                                    Capsule().fill(RecourseColor.ledger)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .recourseGlassField(cornerRadius: 26)

            // Expiry is not a nicety, it is the writer's protection: an uncashed cheque
            // stops being a liability instead of hanging over the balance forever.
            Text("Uncashed after \(validity.label), it stops being cashable and the amount is yours again.")
                .font(.recourse(11, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var memoField: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("What it is for")

            TextField("Optional", text: $memoText, axis: .vertical)
                .font(.recourse(14, .medium))
                .foregroundStyle(RecourseColor.nightText)
                .focused($focus, equals: .memo)
                .lineLimit(1...3)
                .padding(.horizontal, 18)
                .padding(.vertical, 17)
                .recourseGlassField()
        }
    }

    private var promiseNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RecourseColor.nightMuted)
                .frame(width: 16)
            // The three things someone must understand before signing one, in the order
            // they matter: it is not spent yet, it is not bearer, and it is reversible
            // until it is not.
            Text("Nothing moves until they cash it. Only the person you name can, even if the cheque leaks, and you can void it any time before they do.")
                .font(.recourse(11.5, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
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

    private var signBar: some View {
        VStack(spacing: 8) {
            Button(action: sign) {
                HStack(spacing: 10) {
                    if writing { ProgressView().tint(.white) }
                    Text(writing ? "Signing…" : signTitle)
                    if !writing, canSign {
                        Image(systemName: "faceid")
                    }
                }
                .font(.recourse(16, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSign || writing)
            .opacity(canSign || writing ? 1 : 0.45)

            Text("Free to write. Only cashing costs gas, and they pay it.")
                .font(.recourse(10, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 6)
        .recourseBottomFade()
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.recourse(10, .semibold))
            .kerning(1.2)
            .foregroundStyle(RecourseColor.nightMuted)
    }

    // MARK: State

    private var trimmedRecipient: String {
        recipientText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var looksLikeAddress: Bool {
        trimmedRecipient.hasPrefix("0x") || trimmedRecipient.hasPrefix("0X")
    }

    private var recipient: EthereumAddress? {
        if let direct = try? EthereumAddress(trimmedRecipient) { return direct }
        guard let resolvedHandle else { return nil }
        return try? EthereumAddress(resolvedHandle.address)
    }

    private var payeeName: String {
        if let resolvedHandle { return "@\(resolvedHandle.handle)" }
        if let recipient { return recipient.shortened }
        return trimmedRecipient
    }

    private var amount: USDCAmount? {
        guard let value = try? USDCAmount(decimalString: amountText), value.baseUnits > 0 else {
            return nil
        }
        return value
    }

    private var available: USDCAmount {
        book.available(balance: environment.paymentStore.balance)
    }

    private var canSign: Bool {
        guard let amount, recipient != nil else { return false }
        return amount.baseUnits <= available.baseUnits
    }

    private var signTitle: String {
        guard let amount else { return "Write cheque" }
        return "Write \(amount.decimalString) USDC"
    }

    /// Debounced, and skipped entirely for anything that already parses as an address.
    private func resolveRecipient() async {
        resolvedHandle = nil
        handleProblem = nil

        let typed = trimmedRecipient
        guard !typed.isEmpty, (try? EthereumAddress(typed)) == nil, !looksLikeAddress else { return }

        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }

        resolvingHandle = true
        defer { resolvingHandle = false }
        do {
            let found = try await environment.makeHandleAPIClient().resolve(handle: typed)
            guard typed == trimmedRecipient else { return }
            resolvedHandle = found
        } catch let error as HandleAPIError {
            guard typed == trimmedRecipient else { return }
            handleProblem = error.message
        } catch {
            guard typed == trimmedRecipient else { return }
            handleProblem = "Could not reach the directory."
        }
    }

    private func sign() {
        guard canSign, !writing, let amount, let recipient else { return }
        focus = nil
        writing = true
        problem = nil

        Task {
            do {
                let workflow = try environment.makeChequeWorkflow()
                let committed = book.committed
                let stored = try await environment.accountSession.withAccessToken { token in
                    try await workflow.write(
                        to: recipient,
                        amount: amount,
                        validity: validity,
                        memo: memoText,
                        committed: committed,
                        accessToken: token
                    )
                }
                await book.refresh(force: true)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                written = stored
            } catch {
                problem = message(for: error)
            }
            writing = false
        }
    }

    private func message(for error: any Error) -> String {
        switch error {
        case ChequeError.zeroAmount:
            "Enter an amount above zero."
        case ChequeError.selfCheque:
            "That is your own wallet. Write the cheque to someone else."
        case ChequeError.overcommitted(let available):
            "You can write up to \(available.formatted) right now. The rest of your balance is promised to cheques you have already written."
        case AccountSessionError.signedOut:
            "Sign in to write a cheque."
        case is ChequeAPIError:
            (error as? ChequeAPIError)?.message ?? "The cheque could not be saved."
        case TransactionAuthorizationError.cancelled:
            "Signing was cancelled."
        case TransactionAuthorizationError.unavailable:
            "Set a device passcode or Face ID before writing a cheque."
        default:
            "The cheque could not be written. Please try again."
        }
    }
}

/// The moment after signing: the cheque itself, and the one thing left to do with it.
private struct ChequeWrittenView: View {
    let stored: StoredCheque
    let counterpartyName: String
    let onDone: () -> Void

    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                Text("Cheque written")
                    .font(.recourse(26, .bold))
                    .foregroundStyle(RecourseColor.nightText)

                ChequePaper(
                    entry: ChequeEntry(stored: stored, standing: .cashable),
                    counterpartyName: counterpartyName,
                    mine: true
                )
                // Drops in as if torn from a book, which is the one animation this
                // screen earns.
                .rotation3DEffect(.degrees(revealed ? 0 : 34), axis: (x: 1, y: 0, z: 0), anchor: .top)
                .offset(y: revealed ? 0 : -24)
                .opacity(revealed ? 1 : 0)

                Text("\(counterpartyName) can cash it whenever they like. Nothing leaves your balance until they do.")
                    .font(.recourse(12.5, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .opacity(revealed ? 1 : 0)
            }

            Spacer()

            Button("Done", action: onDone)
                .buttonStyle(RecoursePrimaryButtonStyle())
        }
        .padding(24)
        .background(RecourseColor.night.ignoresSafeArea())
        .task {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.78)) {
                revealed = true
            }
        }
    }
}
