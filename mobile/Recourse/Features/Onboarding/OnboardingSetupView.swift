import SwiftUI
import UIKit

enum OnboardingRole: String, CaseIterable, Codable, Sendable {
    case buyer = "Buyer"
    case merchant = "Merchant"

    var detail: String {
        switch self {
        case .buyer: "Pay in USDC with terms and verifiable protection."
        case .merchant: "Accept protected payments and receive funds quickly."
        }
    }

    var icon: String {
        switch self {
        case .buyer: "person.crop.circle.fill"
        case .merchant: "storefront.fill"
        }
    }
}

struct OnboardingWalletSetupView: View {
    let signer: any BuyerSigner
    /// Absent only in previews, where there is no server to provision against.
    let smartAccounts: SmartAccountStore?
    /// Needed only for the way back in when the account already exists elsewhere.
    var environment: AppEnvironment? = nil
    let onBack: () -> Void
    let onContinue: (EthereumAddress) -> Void

    @State private var walletAddress: EthereumAddress?
    @State private var errorMessage: String?
    @State private var isPreparing = false
    @State private var hasCopiedAddress = false
    /// The server has this account's wallet under keys this phone does not hold.
    @State private var needsRecovery = false
    @State private var showsCloudKeyRecovery = false
    @State private var showsPhoneRestore = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760

            VStack(alignment: .leading, spacing: compact ? 18 : 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BUYER WALLET")
                        .recourseEyebrow()
                    Text("Two keys on this iPhone. One tap to pay.")
                        .font(RecourseTypography.display(size: compact ? 32 : 38))
                        .foregroundStyle(RecourseColor.ink)
                    Text("A Device Key in this iPhone's Secure Enclave and a Cloud Key in your iCloud sign every payment together. Neither works alone, and Recourse holds neither.")
                        .font(.recourse(15))
                        .foregroundStyle(RecourseColor.muted)
                        .lineSpacing(2)
                }

                walletCard

                if needsRecovery, environment != nil {
                    recoveryRoute
                } else if let errorMessage {
                    HStack(spacing: 12) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(RecourseColor.ledger)
                        Spacer()
                        Button("Try again") {
                            Task { await prepareWallet() }
                        }
                        .font(.recourse(13, .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    if let walletAddress {
                        onContinue(walletAddress)
                    }
                } label: {
                    if isPreparing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(RecoursePrimaryButtonStyle())
                .disabled(walletAddress == nil || isPreparing)
                .opacity(walletAddress == nil ? 0.55 : 1)
            }
            .padding(.horizontal, 22)
            .padding(.top, compact ? 18 : 24)
            .padding(.bottom, max(proxy.safeAreaInsets.bottom, 18))
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            walletSetupAppBar
        }
        .background(RecourseColor.canvas.ignoresSafeArea())
        .task {
            await prepareWallet()
        }
        .sheet(isPresented: $showsCloudKeyRecovery, onDismiss: { Task { await checkAfterRecovery() } }) {
            if let environment {
                NavigationStack { WalletRecoveryView(environment: environment) }
                    .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: $showsPhoneRestore, onDismiss: { Task { await checkAfterRecovery() } }) {
            if let environment {
                NavigationStack { RestoreDeviceView(environment: environment) }
                    .preferredColorScheme(.dark)
            }
        }
    }

    // The account exists and its keys are elsewhere. Two steps, in order: the Cloud
    // Key comes back from its PIN backup, then the emailed code swaps this phone in
    // as the Device Key. Provisioning again would only be refused again.
    private var recoveryRoute: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This account already has a wallet, and its keys are not on this phone.")
                .font(.recourse(14, .semibold))
                .foregroundStyle(RecourseColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Bring the Cloud Key back with your recovery PIN first, then restore this phone with the code we email you.")
                .font(.recourse(12.5))
                .foregroundStyle(RecourseColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                recoveryButton("1. Cloud Key", filled: true) { showsCloudKeyRecovery = true }
                recoveryButton("2. This phone", filled: false) { showsPhoneRestore = true }
            }
        }
        .padding(16)
        .background(RecourseColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(RecourseColor.line, lineWidth: 1))
    }

    private func recoveryButton(_ title: String, filled: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title)
                .font(.recourse(13, .semibold))
                .foregroundStyle(filled ? .white : RecourseColor.ledger)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(filled ? RecourseColor.ledger : RecourseColor.mint, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// After either sheet closes: if the phone now holds the account's Device Key,
    /// the Safe is the wallet and the flow can carry on.
    @MainActor
    private func checkAfterRecovery() async {
        guard let smartAccounts else { return }
        await smartAccounts.refresh()
        if smartAccounts.isLive, let record = smartAccounts.record {
            walletAddress = EthereumAddress(trusted: record.safe)
            needsRecovery = false
            errorMessage = nil
        }
    }

    private var walletSetupAppBar: some View {
        HStack {
            RecourseGlassIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back",
                action: onBack
            )
            Spacer()
            Label("SECURE SETUP", systemImage: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(RecourseColor.ledger)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(RecourseColor.canvas)
    }

    private var walletCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
                Spacer()
                Text("ARC TESTNET")
                    .font(.recourse(10, .bold))
                    .tracking(0.8)
                    .foregroundStyle(RecourseColor.muted)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(walletAddress == nil ? "Setting up your account" : "Account ready")
                    .font(.recourse(16, .semibold))
                    .foregroundStyle(RecourseColor.ink)
                HStack(spacing: 10) {
                    Text(walletAddress.map(shortAddress) ?? progressText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.muted)
                        .contentTransition(.numericText())
                    Spacer()
                    if walletAddress != nil {
                        Button(action: copyWalletAddress) {
                            Label(
                                hasCopiedAddress ? "Copied" : "Copy",
                                systemImage: hasCopiedAddress ? "checkmark" : "doc.on.doc"
                            )
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(RecourseColor.ledger)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            Label("Made on this iPhone. Recourse never holds a spending key.", systemImage: "checkmark.shield.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RecourseColor.ledger)
        }
        .padding(18)
        .background(RecourseColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(RecourseColor.line, lineWidth: 1)
        }
    }

    private var progressText: String {
        if let smartAccounts, case .provisioning(let message) = smartAccounts.phase {
            return message + "..."
        }
        return "Making your keys..."
    }

    @MainActor
    private func prepareWallet() async {
        guard walletAddress == nil, !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }

        do {
            if let smartAccounts {
                // The account is the Safe; provisioning makes both keys, mints the
                // recovery key and deploys it. Idempotent, so Try again is safe.
                let record = try await smartAccounts.provision()
                walletAddress = EthereumAddress(trusted: record.safe)
            } else {
                walletAddress = try await signer.address()
            }
        } catch {
            if case SmartAccountAPIError.rejected(409, _) = error {
                needsRecovery = true
            }
            errorMessage = (error as? SmartAccountAPIError)?.message
                ?? "Recourse could not set up your account. Please try again."
        }
    }

    private func shortAddress(_ address: EthereumAddress) -> String {
        let value = address.value
        return "\(value.prefix(8))...\(value.suffix(6))"
    }

    private func copyWalletAddress() {
        guard let walletAddress else { return }
        UIPasteboard.general.string = walletAddress.value
        withAnimation(.snappy(duration: 0.2)) {
            hasCopiedAddress = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            hasCopiedAddress = false
        }
    }
}
