import SwiftUI

// LP access to the settlement vault: deposit idle USDC, fund T+0 merchant
// advances, and earn the advance fees plus escrow float yield. Every number on
// this screen is a live vault read; deposits and withdrawals are real
// transactions signed on this device.
struct EarnView: View {
    let environment: AppEnvironment

    @State private var vaultState: VaultState?
    @State private var loadError: String?
    @State private var activeSheet: VaultSheet?

    private enum VaultSheet: String, Identifiable {
        case deposit
        case withdraw

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                positionCard
                if let vaultState {
                    statsCard(vaultState)
                }
                explainer
                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RecourseColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .background(Color.white)
        .navigationTitle("Earn")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $activeSheet) { sheet in
            VaultActionSheet(
                environment: environment,
                mode: sheet == .deposit ? .deposit : .withdraw,
                vaultState: vaultState
            ) {
                await load()
            }
            .presentationDetents([.medium])
        }
    }

    private func load() async {
        do {
            let owner = try await environment.buyerSigner.address()
            let gateway = try environment.makeContractGateway()
            vaultState = try await gateway.vaultState(of: owner)
            loadError = nil
        } catch {
            loadError = "Live vault data is unavailable right now. Pull to refresh."
        }
    }

    private var positionCard: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(RecourseColor.ledger.opacity(0.1))
                .frame(width: 170, height: 170)
                .blur(radius: 46)
                .offset(x: 54, y: -62)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Settlement vault", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text("ARC TESTNET")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.35)
                        .foregroundStyle(.white.opacity(0.68))
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(positionValue)
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.72)
                        Text("your position")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    Text(positionSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                }
                HStack(spacing: 10) {
                    Button {
                        activeSheet = .deposit
                    } label: {
                        Text("Deposit")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RecourseColor.ledger, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        activeSheet = .withdraw
                    } label: {
                        Text("Withdraw")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(.white.opacity(0.12), in: Capsule())
                            .overlay { Capsule().stroke(.white.opacity(0.16), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled((vaultState?.myShares ?? 0) == 0)
                    .opacity((vaultState?.myShares ?? 0) == 0 ? 0.45 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(RecourseColor.ink, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: RecourseColor.ink.opacity(0.15), radius: 18, y: 10)
    }

    private var positionValue: String {
        guard let vaultState else { return "$—" }
        return dollars(vaultState.myValue)
    }

    private var positionSubtitle: String {
        guard let vaultState else { return "Reading the vault on Arc…" }
        if vaultState.myShares == 0 {
            return "Deposit USDC to start earning vault fees and yield"
        }
        return "\(sharesText(vaultState.myShares)) shares · price \(priceText(vaultState.sharePrice))"
    }

    private func statsCard(_ state: VaultState) -> some View {
        VStack(spacing: 0) {
            statRow("In the vault", dollars(state.totalAssets))
            Divider()
            statRow("Advancing merchants now", dollars(state.outstanding))
            Divider()
            statRow("Share price", priceText(state.sharePrice))
        }
        .padding(.horizontal, 16)
        .background(RecourseColor.clay, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RecourseColor.muted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(RecourseColor.ink)
                .monospacedDigit()
        }
        .padding(.vertical, 13)
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How the vault earns")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(RecourseColor.ink)
            explainerRow("bolt.fill", "Deposits pay merchants instantly", "The vault advances protected sales at T+0 and takes over the escrow claim.")
            explainerRow("percent", "Fees and yield accrue to shares", "Each advance books a fee, and escrowed funds earn float yield until settlement.")
            explainerRow("shield.lefthalf.filled", "Risk is bounded, not vague", "Refund exposure is capped by immutable policies and per-merchant limits, all onchain.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(.white.opacity(0.78), lineWidth: 0.9)
        }
    }

    private func explainerRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RecourseColor.ink)
                .frame(width: 34, height: 34)
                .background(RecourseColor.clay, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RecourseColor.ink)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(RecourseColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func dollars(_ amount: USDCAmount) -> String {
        String(format: "$%.2f", Double(amount.baseUnits) / Double(USDCAmount.base))
    }

    private func sharesText(_ shares: UInt64) -> String {
        String(format: "%.2f", Double(shares) / Double(USDCAmount.base))
    }

    private func priceText(_ price: Double) -> String {
        String(format: "%.4f", price)
    }
}

private enum VaultActionError: Error {
    case reverted
}

private struct VaultActionSheet: View {
    enum Mode {
        case deposit
        case withdraw
    }

    let environment: AppEnvironment
    let mode: Mode
    let vaultState: VaultState?
    let onFinished: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var isWorking = false
    @State private var stage: String?
    @State private var errorMessage: String?
    @State private var succeeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(mode == .deposit ? "Deposit USDC" : "Withdraw USDC")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(RecourseColor.ink)

            if succeeded {
                successBody
            } else {
                entryBody
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private var successBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
            Text(mode == .deposit ? "Deposited on Arc" : "Withdrawn on Arc")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(RecourseColor.ink)
            Button("Done") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RecourseColor.ledger, in: Capsule())
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
    }

    private var entryBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                TextField("0.00", text: $amountText)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 44, weight: .medium, design: .rounded))
                    .minimumScaleFactor(0.65)
                    .keyboardType(.decimalPad)
                Text("USDC")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(RecourseColor.muted)
            }
            .frame(maxWidth: .infinity)

            HStack {
                Text(capText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RecourseColor.muted)
                Spacer()
                Button("Max") { amountText = maxText }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RecourseColor.ledger)
                    .buttonStyle(.plain)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RecourseColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button {
                    submit()
                } label: {
                    HStack(spacing: 10) {
                        if isWorking { ProgressView().tint(.white) }
                        Text(isWorking ? (stage ?? "Working…") : confirmLabel)
                        if !isWorking, canSubmit { Image(systemName: "faceid") }
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(RecourseColor.ledgerDeep, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .opacity(canSubmit || isWorking ? 1 : 0.5)

                Text(mode == .deposit
                    ? "Two Face ID confirmations: approve, then deposit."
                    : "Face ID confirms the withdrawal on Arc Testnet.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(RecourseColor.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var amount: USDCAmount? {
        try? USDCAmount(decimalString: amountText)
    }

    private var confirmLabel: String {
        mode == .deposit ? "Deposit \(amount?.formatted ?? "USDC")" : "Withdraw \(amount?.formatted ?? "USDC")"
    }

    private var capText: String {
        switch mode {
        case .deposit:
            if let balance = environment.paymentStore.balance {
                return "Available: \(balance.formatted)"
            }
            return "Checking wallet balance…"
        case .withdraw:
            if let vaultState {
                return "In the vault: \(vaultState.myValue.formatted)"
            }
            return "Reading your position…"
        }
    }

    private var maxText: String {
        let cap: UInt64
        switch mode {
        case .deposit: cap = environment.paymentStore.balance?.baseUnits ?? 0
        case .withdraw: cap = vaultState?.myValue.baseUnits ?? 0
        }
        return String(format: "%.6f", Double(cap) / Double(USDCAmount.base))
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private var canSubmit: Bool {
        guard let amount, amount.baseUnits > 0, !isWorking else { return false }
        if mode == .withdraw {
            guard let vaultState, vaultState.shares(for: amount) > 0 else { return false }
        }
        return true
    }

    private func submit() {
        guard let amount, !isWorking else { return }
        isWorking = true
        errorMessage = nil

        Task {
            do {
                let gateway = try environment.makeContractGateway()
                switch mode {
                case .deposit:
                    stage = "Approving USDC…"
                    let approval = try await gateway.approveVaultUSDC(amount: amount)
                    guard try await gateway.waitForReceipt(transactionHash: approval).outcome == .confirmed else {
                        throw VaultActionError.reverted
                    }
                    stage = "Depositing on Arc…"
                    let deposit = try await gateway.vaultDeposit(amount: amount)
                    guard try await gateway.waitForReceipt(transactionHash: deposit).outcome == .confirmed else {
                        throw VaultActionError.reverted
                    }
                case .withdraw:
                    guard let vaultState else { throw VaultActionError.reverted }
                    stage = "Withdrawing on Arc…"
                    let withdrawal = try await gateway.vaultWithdraw(shares: vaultState.shares(for: amount))
                    guard try await gateway.waitForReceipt(transactionHash: withdrawal).outcome == .confirmed else {
                        throw VaultActionError.reverted
                    }
                }
                await environment.paymentStore.refreshBuyer()
                await onFinished()
                succeeded = true
            } catch {
                errorMessage = failureMessage(error)
            }
            isWorking = false
            stage = nil
        }
    }

    private func failureMessage(_ error: any Error) -> String {
        switch error {
        case VaultActionError.reverted:
            "Arc reverted the transaction. Nothing moved."
        case TransactionAuthorizationError.cancelled:
            "The transaction was cancelled."
        case TransactionAuthorizationError.unavailable:
            "Set a device passcode or Face ID first."
        case ContractReadError.rpc(let code, let message):
            "Arc RPC error \(code): \(message)"
        default:
            "The transaction could not be completed. Please try again."
        }
    }
}
