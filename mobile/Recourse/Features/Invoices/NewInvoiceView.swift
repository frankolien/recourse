import SwiftUI
import UIKit

/// Ask someone for money.
///
/// Nothing here touches the chain and nothing is signed: an invoice is a request, and
/// the only signature that ever exists is the payer's. That is why this screen has no
/// balance on it. What you are owed does not depend on what you hold.
struct NewInvoiceView: View {
    let environment: AppEnvironment

    @State private var amountText = ""
    @State private var payerText = ""
    @State private var memoText = ""
    @State private var terms: InvoiceTerms = .week
    @State private var resolvedHandle: ResolvedHandle?
    @State private var resolvingHandle = false
    @State private var handleProblem: String?
    @State private var sending = false
    @State private var problem: String?
    @State private var issued: StoredInvoice?
    @FocusState private var focus: Field?

    private enum Field { case amount, payer, memo }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                amountEntry
                payerField
                    .padding(.top, 26)
                termsPicker
                    .padding(.top, 26)
                memoField
                    .padding(.top, 26)
                if let problem {
                    refusal(problem)
                        .padding(.top, 20)
                }
                note
                    .padding(.top, 26)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(RecourseColor.night)
        .navigationTitle("Request money")
        .navigationBarTitleDisplayMode(.inline)
        .recourseKeyboardDismissal()
        .safeAreaInset(edge: .bottom) { sendBar }
        .task(id: payerText) { await resolvePayer() }
        .fullScreenCover(item: $issued) { invoice in
            InvoiceSentView(
                invoice: invoice,
                payerName: payeeName,
                onDone: {
                    issued = nil
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
        }
    }

    private var payerField: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("Bill to")
            HStack(spacing: 10) {
                TextField("@name or wallet address", text: $payerText)
                    .font(
                        looksLikeAddress
                            ? .system(size: 13, weight: .medium, design: .monospaced)
                            : .recourse(16, .medium)
                    )
                    .foregroundStyle(RecourseColor.nightText)
                    .focused($focus, equals: .payer)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if resolvingHandle {
                    ProgressView().controlSize(.small).tint(RecourseColor.nightMuted)
                }
                Button {
                    if let pasted = UIPasteboard.general.string {
                        payerText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
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

            if let resolvedHandle, payer != nil {
                Label(
                    "@\(resolvedHandle.handle) · \(EthereumAddress(trusted: resolvedHandle.address).shortened)",
                    systemImage: "at.circle.fill"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
            } else if let handleProblem, payer == nil {
                Text(handleProblem)
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
        }
    }

    private var termsPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("Terms")
            HStack(spacing: 8) {
                ForEach(InvoiceTerms.allCases) { option in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.2)) { terms = option }
                    } label: {
                        Text(option.label)
                            .font(.recourse(12.5, .semibold))
                            .foregroundStyle(terms == option ? .white : RecourseColor.nightText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background {
                                if terms == option {
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

            Text(terms.detail + ". After that it can no longer be paid or collected.")
                .font(.recourse(11, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var memoField: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("What it is for")
            TextField("Design work, week of the 3rd", text: $memoText, axis: .vertical)
                .font(.recourse(14, .medium))
                .foregroundStyle(RecourseColor.nightText)
                .focused($focus, equals: .memo)
                .lineLimit(1...3)
                .padding(.horizontal, 18)
                .padding(.vertical, 17)
                .recourseGlassField()
            // Required, not optional, because an unexplained demand for money is the
            // thing people are right to ignore.
            Text("Required. They see this before they decide.")
                .font(.recourse(11, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
        }
    }

    private var note: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RecourseColor.nightMuted)
                .frame(width: 16)
            Text("The amount, the date and who pays are fixed the moment you send this. They can sign it or not, but nothing about it can be changed after.")
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

    private var sendBar: some View {
        VStack(spacing: 8) {
            Button(action: send) {
                HStack(spacing: 10) {
                    if sending { ProgressView().tint(.white) }
                    Text(sending ? "Sending…" : sendTitle)
                }
                .font(.recourse(16, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSend || sending)
            .opacity(canSend || sending ? 1 : 0.45)

            Text("Nothing is signed and nothing moves until they pay.")
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

    private var trimmedPayer: String {
        payerText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var looksLikeAddress: Bool {
        trimmedPayer.hasPrefix("0x") || trimmedPayer.hasPrefix("0X")
    }

    private var payer: EthereumAddress? {
        if let direct = try? EthereumAddress(trimmedPayer) { return direct }
        guard let resolvedHandle else { return nil }
        return try? EthereumAddress(resolvedHandle.address)
    }

    private var payeeName: String {
        if let resolvedHandle { return "@\(resolvedHandle.handle)" }
        if let payer { return payer.shortened }
        return trimmedPayer
    }

    private var amount: USDCAmount? {
        guard let value = try? USDCAmount(decimalString: amountText), value.baseUnits > 0 else {
            return nil
        }
        return value
    }

    private var canSend: Bool {
        amount != nil
            && payer != nil
            && !memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendTitle: String {
        guard let amount else { return "Send invoice" }
        return "Request \(amount.decimalString) USDC"
    }

    private func resolvePayer() async {
        resolvedHandle = nil
        handleProblem = nil

        let typed = trimmedPayer
        guard !typed.isEmpty, (try? EthereumAddress(typed)) == nil, !looksLikeAddress else { return }

        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }

        resolvingHandle = true
        defer { resolvingHandle = false }
        do {
            let found = try await environment.makeHandleAPIClient().resolve(handle: typed)
            guard typed == trimmedPayer else { return }
            resolvedHandle = found
        } catch let error as HandleAPIError {
            guard typed == trimmedPayer else { return }
            handleProblem = error.message
        } catch {
            guard typed == trimmedPayer else { return }
            handleProblem = "Could not reach the directory."
        }
    }

    private func send() {
        guard canSend, !sending, let amount, let payer else { return }
        focus = nil
        sending = true
        problem = nil

        Task {
            do {
                let workflow = try environment.makeInvoiceWorkflow()
                let stored = try await environment.accountSession.withAccessToken { token in
                    try await workflow.issue(
                        to: payer,
                        amount: amount,
                        terms: terms,
                        memo: memoText,
                        accessToken: token
                    )
                }
                await environment.invoiceBook.refresh(force: true)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                issued = stored
            } catch {
                problem = message(for: error)
            }
            sending = false
        }
    }

    private func message(for error: any Error) -> String {
        switch error {
        case InvoiceError.zeroAmount: "Enter an amount above zero."
        case InvoiceError.selfInvoice: "That is your own wallet. Bill someone else."
        case InvoiceError.missingMemo: "Say what the invoice is for."
        case AccountSessionError.signedOut: "Sign in to send an invoice."
        case is InvoiceAPIError: (error as? InvoiceAPIError)?.message ?? "The invoice could not be sent."
        default: "The invoice could not be sent. Please try again."
        }
    }
}

/// The moment after sending. No signature happened here, so the copy is careful not to
/// imply anything has been agreed yet.
private struct InvoiceSentView: View {
    let invoice: StoredInvoice
    let payerName: String
    let onDone: () -> Void

    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: "paperplane.circle.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
                    .scaleEffect(revealed ? 1 : 0.6)

                Text("Invoice sent")
                    .font(.recourse(28, .bold))
                    .foregroundStyle(RecourseColor.nightText)

                Text(invoice.usdc.formatted)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(RecourseColor.nightText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("\(payerName) has until \(invoice.dueAt.formatted(date: .abbreviated, time: .omitted)) to pay it. You will see it here the moment they do.")
                    .font(.recourse(12.5, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
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
