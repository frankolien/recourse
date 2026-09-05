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
    @State private var showsCardPicker = false
    @AppStorage(WalletCardStyle.defaultsKey) private var cardStyleRaw = WalletCardStyle.ink.rawValue

    private var cardStyle: WalletCardStyle {
        WalletCardStyle.stored(rawValue: cardStyleRaw)
    }

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
                        .foregroundStyle(RecourseColor.nightMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .background(RecourseColor.night)
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
        .sheet(isPresented: $showsCardPicker) {
            WalletCardStylePicker(selectedRawValue: $cardStyleRaw)
                .presentationDetents([.medium, .large])
        }
    }

    /// The position as last read, then the chain. A failed read keeps the last
    /// position on screen and says the figures are old.
    private func load() async {
        if vaultState == nil {
            vaultState = SnapshotCache.shared.load(VaultState.self, key: "earn", scope: ActiveAccount.scope)
        }
        do {
            let owner = try await environment.buyerSigner.address()
            let gateway = try environment.makeContractGateway()
            let state = try await gateway.vaultState(of: owner)
            vaultState = state
            SnapshotCache.shared.save(state, key: "earn", scope: ActiveAccount.scope)
            loadError = nil
        } catch {
            loadError = vaultState == nil
                ? "Live vault data is unavailable right now. Pull to refresh."
                : "Arc is not answering. These figures are from the last read."
        }
    }

    private var positionCard: some View {
        ZStack(alignment: .topTrailing) {
            if cardStyle.showsGlow {
                Circle()
                    .fill(RecourseColor.ledger.opacity(0.1))
                    .frame(width: 170, height: 170)
                    .blur(radius: 46)
                    .offset(x: 54, y: -62)
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Settlement vault", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text("ARC TESTNET")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.35)
                        .foregroundStyle(cardStyle.textSecondary)
                    Button {
                        showsCardPicker = true
                    } label: {
                        Image(systemName: "paintbrush.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(cardStyle.textSecondary)
                            .frame(width: 26, height: 26)
                            .background(cardStyle.chipFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change card style")
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(positionValue)
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.72)
                        Text("your position")
                            .font(.recourse(13, .semibold))
                            .foregroundStyle(cardStyle.textSecondary)
                    }
                    Text(positionSubtitle)
                        .font(.recourse(12, .medium))
                        .foregroundStyle(cardStyle.textSecondary)
                }
                HStack(spacing: 10) {
                    Button {
                        activeSheet = .deposit
                    } label: {
                        Text("Deposit")
                            .font(.recourse(14, .semibold))
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
                            .font(.recourse(14, .semibold))
                            .foregroundStyle(cardStyle.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(cardStyle.chipFill, in: Capsule())
                            .overlay { Capsule().stroke(cardStyle.chipStroke, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled((vaultState?.myShares ?? 0) == 0)
                    .opacity((vaultState?.myShares ?? 0) == 0 ? 0.45 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(cardStyle.textPrimary)
        .modifier(WalletCardSurface(style: cardStyle))
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
        .padding(.horizontal, 2)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.recourse(13, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(RecourseColor.nightText)
                .monospacedDigit()
        }
        .padding(.vertical, 13)
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How the vault earns")
                .font(.recourse(15, .bold))
                .foregroundStyle(RecourseColor.nightText)
            explainerRow("bolt.fill", "Deposits pay merchants instantly", "The vault advances protected sales at T+0 and takes over the escrow claim.")
            explainerRow("percent", "Fees and yield accrue to shares", "Each advance books a fee, and escrowed funds earn float yield until settlement.")
            explainerRow("shield.lefthalf.filled", "Risk is bounded, not vague", "Refund exposure is capped by immutable policies and per-merchant limits, all onchain.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
    }

    private func explainerRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RecourseColor.nightText)
                .frame(width: 34, height: 34)
                .background(RecourseColor.nightChip, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.recourse(13, .bold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(detail)
                    .font(.recourse(11.5))
                    .foregroundStyle(RecourseColor.nightMuted)
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
    @State private var celebrationRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(mode == .deposit ? "Deposit USDC" : "Withdraw USDC")
                .font(.recourse(20, .bold))
                .foregroundStyle(RecourseColor.nightText)

            if succeeded {
                successBody
            } else {
                entryBody
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RecourseColor.night)
    }

    private var successBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .scaleEffect(celebrationRevealed ? 1 : 0.4)
            Text(mode == .deposit ? "Deposited on Arc" : "Withdrawn on Arc")
                .font(.recourse(16, .bold))
                .foregroundStyle(RecourseColor.nightText)
                .opacity(celebrationRevealed ? 1 : 0)
            Button("Done") { dismiss() }
                .font(.recourse(15, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RecourseColor.ledger, in: Capsule())
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .task {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                celebrationRevealed = true
            }
        }
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
                    .font(.recourse(14, .bold))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            .frame(maxWidth: .infinity)

            HStack {
                Text(capText)
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                Spacer()
                Button("Max") { amountText = maxText }
                    .font(.recourse(12, .bold))
                    .foregroundStyle(RecourseColor.ledger)
                    .buttonStyle(.plain)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RecourseColor.nightText)
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
                    .font(.recourse(10, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
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
