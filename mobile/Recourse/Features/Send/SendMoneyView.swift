import SwiftUI
import UIKit

// Person-to-person USDC send. Not the protected path on purpose: the banner says so,
// and points buyers back to protected checkouts for purchases. That contrast is part of
// the product: a raw transfer is what every other wallet gives you; Recourse's checkout
// is what makes a payment safe.
struct SendMoneyView: View {
    let environment: AppEnvironment

    @State private var recipientText = ""
    @State private var amountText = ""
    @State private var isSending = false
    @State private var progress: SendProgress?
    @State private var errorMessage: String?
    @State private var sent: SendResult?
    @State private var showsAddressBook = false
    @State private var showsSaveRecipient = false
    // A typed name is resolved against the directory rather than parsed, so this
    // cannot be a computed property the way an address can.
    @State private var resolvedHandle: ResolvedHandle?
    @State private var resolvingHandle = false
    @State private var handleProblem: String?
    @AppStorage(BuyerSettingKey.paymentLimitBaseUnits) private var limitBaseUnits = 0
    @AppStorage(BuyerSettingKey.confirmPaymentsWithBiometrics) private var confirmWithBiometrics = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                amountEntry
                recipientField
                noProtectionBanner
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RecourseColor.ledger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RecourseColor.night)
        .navigationTitle("Send USDC")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: recipientText) {
            await resolveRecipient()
        }
        .safeAreaInset(edge: .bottom) {
            sendActionBar
        }
        .fullScreenCover(item: $sent) { result in
            SendSuccessView(result: result) {
                sent = nil
                environment.router.reset()
            }
        }
        .sheet(isPresented: $showsAddressBook) {
            SavedRecipientPicker(store: environment.addressBook) { picked in
                recipientText = picked.address
            }
        }
        .sheet(isPresented: $showsSaveRecipient) {
            RecipientEditorView(
                store: environment.addressBook,
                prefilledAddress: recipient?.value ?? ""
            )
        }
        .task {
            await environment.paymentStore.refreshBuyer()
        }
    }

    private var amountEntry: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                TextField("0.00", text: $amountText)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 52, weight: .medium, design: .rounded))
                    .minimumScaleFactor(0.65)
                    .keyboardType(.decimalPad)
                Text("USDC")
                    .font(.recourse(15, .bold))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            .frame(maxWidth: .infinity)
            if let balance = environment.paymentStore.balance {
                Text("Available: \(balance.formatted)")
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
        }
        .padding(.vertical, 20)
    }

    private var recipientField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("To")
                .font(.recourse(16, .bold))
                .foregroundStyle(RecourseColor.nightText)
            HStack(spacing: 10) {
                // Monospaced only while it looks like an address: it makes hex
                // checkable character by character and makes a name look like a
                // serial number.
                TextField("@name or wallet address", text: $recipientText)
                    .font(
                        looksLikeAddress
                            ? .system(size: 13, weight: .medium, design: .monospaced)
                            : .recourse(15, .medium)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if resolvingHandle {
                    ProgressView()
                        .controlSize(.small)
                        .tint(RecourseColor.nightMuted)
                }
                if !environment.addressBook.recipients.isEmpty {
                    Button {
                        showsAddressBook = true
                    } label: {
                        Image(systemName: "person.crop.rectangle.stack.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(RecourseColor.ledger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose a saved address")
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
                .accessibilityLabel("Paste address")
            }
            .padding(.horizontal, 15)
            .frame(height: 52)
            .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 16))
            if let handleProblem, recipient == nil {
                Text(handleProblem)
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.ledger)
            } else if !recipientText.isEmpty, recipient == nil, !resolvingHandle {
                Text("Enter a @name or a wallet address.")
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.ledger)
            }
            if let resolvedHandle, recipient != nil {
                // The name as its owner capitalised it, and the address it currently
                // points at, because the sender is entitled to see where money goes.
                Label(
                    "@\(resolvedHandle.handle) · \(EthereumAddress(trusted: resolvedHandle.address).shortened)",
                    systemImage: "at.circle.fill"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
            }
            if let recipient {
                if let saved = environment.addressBook.recipient(for: recipient.value) {
                    Label("Sending to \(saved.label)", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                } else {
                    Button {
                        showsSaveRecipient = true
                    } label: {
                        Label("Save to address book", systemImage: "plus.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(RecourseColor.ledger)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var noProtectionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RecourseColor.nightText)
            VStack(alignment: .leading, spacing: 3) {
                Text("Direct sends have no protection")
                    .font(.recourse(13, .bold))
                    .foregroundStyle(RecourseColor.nightText)
                Text("This transfer is final, with no dispute or refund path. Buying something? Ask the seller for a Recourse checkout instead.")
                    .font(.recourse(12))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var trimmedRecipient: String {
        recipientText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var looksLikeAddress: Bool {
        trimmedRecipient.hasPrefix("0x") || trimmedRecipient.hasPrefix("0X")
    }

    /// A literal address wins, so paying one is exactly as it was. A name only
    /// resolves through the directory, and only after it comes back.
    private var recipient: EthereumAddress? {
        if let direct = try? EthereumAddress(trimmedRecipient) { return direct }
        guard let resolvedHandle else { return nil }
        return try? EthereumAddress(resolvedHandle.address)
    }

    /// Debounced because the field runs this on every keystroke and each pass is a
    /// network read. Anything that parses as an address is never looked up at all.
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
            // The field may have moved on while the lookup was in flight.
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

    private var amount: USDCAmount? {
        try? USDCAmount(decimalString: amountText)
    }

    private var exceedsLimit: Bool {
        guard let amount else { return false }
        return PaymentLimit.exceeded(amount: amount, limitBaseUnits: limitBaseUnits)
    }

    private var canSend: Bool {
        guard let amount, amount.baseUnits > 0, recipient != nil, !exceedsLimit else { return false }
        return !isSending
    }

    private var sendActionBar: some View {
        VStack(spacing: 9) {
            if exceedsLimit {
                Label(
                    "Above your \(PaymentLimit.formatted(baseUnits: limitBaseUnits)) per-payment limit. Change it in Settings.",
                    systemImage: "gauge.with.dots.needle.100percent"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
            }

            Button {
                submit()
            } label: {
                HStack(spacing: 10) {
                    if isSending { ProgressView().tint(.white) }
                    Text(isSending ? progressLabel : "Send \(amount?.formatted ?? "USDC")")
                    if !isSending, canSend, confirmWithBiometrics {
                        Image(systemName: "faceid")
                    }
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RecourseColor.ledgerDeep, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend || isSending ? 1 : 0.5)

            Text(
                confirmWithBiometrics
                    ? "Face ID confirms this transfer on Arc Testnet"
                    : "Face ID confirmation is off. Turn it on in Settings."
            )
            .font(.recourse(10, .medium))
            .foregroundStyle(RecourseColor.nightMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(RecourseColor.night)
    }

    private var progressLabel: String {
        switch progress {
        case .validating: "Checking transfer…"
        case .checkingFunds: "Checking USDC balance…"
        case .submitted: "Sending on Arc…"
        case .confirmed: "Transfer confirmed"
        case nil: "Sending…"
        }
    }

    private func submit() {
        guard !isSending, canSend, let recipient, let amount else { return }
        isSending = true
        errorMessage = nil
        progress = .validating

        Task {
            do {
                let gateway = try environment.makeContractGateway()
                let sender = try await environment.buyerSigner.address()
                let result = try await SendWorkflow(gateway: gateway).execute(
                    recipient: recipient,
                    amount: amount,
                    sender: sender
                ) { update in
                    await MainActor.run { progress = update }
                }
                await environment.paymentStore.refreshBuyer()
                sent = result
            } catch {
                errorMessage = sendErrorMessage(error)
            }
            isSending = false
        }
    }

    private func sendErrorMessage(_ error: any Error) -> String {
        switch error {
        case SendError.zeroAmount:
            "Enter an amount greater than zero."
        case SendError.selfTransfer:
            "That is this wallet's own address."
        case SendError.insufficientBalance(let available):
            "Your Arc wallet holds \(available.formatted), not enough for this transfer."
        case SendError.transactionReverted:
            "Arc reverted the transfer. Nothing was sent."
        case TransactionAuthorizationError.cancelled:
            "The transfer was cancelled."
        case TransactionAuthorizationError.unavailable:
            "Set a device passcode or Face ID before sending."
        case ContractReadError.rpc(let code, let message):
            "Arc RPC error \(code): \(message)"
        default:
            "The transfer could not be completed. Please try again."
        }
    }
}

extension SendResult: Identifiable {
    var id: String { transactionHash.value }
}

/// Pick-a-recipient sheet backed by the device address book.
private struct SavedRecipientPicker: View {
    let store: AddressBookStore
    let onPick: (SavedRecipient) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.recipients) { recipient in
                Button {
                    onPick(recipient)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipient.label)
                            .font(.recourse(14, .bold))
                            .foregroundStyle(RecourseColor.nightText)
                        Text(recipient.address)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(RecourseColor.nightMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(RecourseColor.night)
            .navigationTitle("Saved addresses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SendSuccessView: View {
    let result: SendResult
    let onDone: () -> Void
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "paperplane.circle.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
                    .scaleEffect(revealed ? 1 : 0.5)
                VStack(spacing: 8) {
                    Text("Sent")
                        .font(.recourse(30, .bold))
                        .foregroundStyle(RecourseColor.nightText)
                    Text(result.amount.formatted)
                        .font(.system(size: 44, weight: .medium, design: .rounded))
                        .foregroundStyle(RecourseColor.nightText)
                    Text("To \(result.recipient.shortened) on Arc Testnet")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                Text(result.transactionHash.shortened)
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
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                revealed = true
            }
        }
    }
}
