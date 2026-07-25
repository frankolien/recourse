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
        .background(Color.white)
        .navigationTitle("Send USDC")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            sendActionBar
        }
        .fullScreenCover(item: $sent) { result in
            SendSuccessView(result: result) {
                sent = nil
                environment.router.reset()
            }
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
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(RecourseColor.muted)
            }
            .frame(maxWidth: .infinity)
            if let balance = environment.paymentStore.balance {
                Text("Available: \(balance.formatted)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RecourseColor.muted)
            }
        }
        .padding(.vertical, 20)
    }

    private var recipientField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("To")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(RecourseColor.ink)
            HStack(spacing: 10) {
                TextField("Wallet address (0x…)", text: $recipientText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
            .background(RecourseColor.surface, in: RoundedRectangle(cornerRadius: 16))
            if !recipientText.isEmpty, recipient == nil {
                Text("That is not a valid wallet address.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RecourseColor.ledger)
            }
        }
    }

    private var noProtectionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RecourseColor.ink)
            VStack(alignment: .leading, spacing: 3) {
                Text("Direct sends have no protection")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Text("This transfer is final, with no dispute or refund path. Buying something? Ask the seller for a Recourse checkout instead.")
                    .font(.system(size: 12))
                    .foregroundStyle(RecourseColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .background(Color(red: 0.97, green: 0.97, blue: 0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var recipient: EthereumAddress? {
        try? EthereumAddress(recipientText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var amount: USDCAmount? {
        try? USDCAmount(decimalString: amountText)
    }

    private var canSend: Bool {
        guard let amount, amount.baseUnits > 0, recipient != nil else { return false }
        return !isSending
    }

    private var sendActionBar: some View {
        VStack(spacing: 9) {
            Button {
                submit()
            } label: {
                HStack(spacing: 10) {
                    if isSending { ProgressView().tint(.white) }
                    Text(isSending ? progressLabel : "Send \(amount?.formatted ?? "USDC")")
                    if !isSending, canSend {
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

            Text("Face ID confirms this transfer on Arc Testnet")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(RecourseColor.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
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
        guard !isSending, let recipient, let amount else { return }
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
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(RecourseColor.ink)
                    Text(result.amount.formatted)
                        .font(.system(size: 44, weight: .medium, design: .rounded))
                        .foregroundStyle(RecourseColor.ink)
                    Text("To \(result.recipient.shortened) on Arc Testnet")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.muted)
                }
                Text(result.transactionHash.shortened)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(RecourseColor.muted)
            }
            .offset(y: revealed ? 0 : 14)
            .opacity(revealed ? 1 : 0)
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(RecoursePrimaryButtonStyle())
        }
        .padding(24)
        .background(Color.white.ignoresSafeArea())
        .task {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                revealed = true
            }
        }
    }
}
