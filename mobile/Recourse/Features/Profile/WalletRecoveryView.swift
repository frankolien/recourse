import SwiftUI

/// Turn recovery on, and restore a wallet onto a device that has none.
///
/// One screen for both because they are the same fact seen from two devices: whether
/// this account's wallet exists anywhere other than the phone in your hand.
struct WalletRecoveryView: View {
    let environment: AppEnvironment

    private enum Stage: Equatable {
        case loading
        /// A wallet here, no backup stored: the only thing to do is protect it.
        case unprotected
        case protected(address: String, updatedAt: String)
        /// A backup exists and this device has no wallet. The restore case, and the
        /// whole reason any of this was built.
        case restorable(address: String)
    }

    @State private var stage: Stage = .loading
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var working = false
    @State private var problem: String?
    @State private var done: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch stage {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                case .unprotected:
                    header(
                        "Protect this wallet",
                        "Choose a PIN. Your key is encrypted with it on this phone, and only the encrypted copy is stored."
                    )
                    pinFields(confirming: true)
                    action("Turn on recovery") { await enableRecovery() }
                case .protected(let address, let updatedAt):
                    header("Recovery is on", "Sign in on another device and unlock with your PIN.")
                    facts(address: address, updatedAt: updatedAt)
                    turnOff
                case .restorable(let address):
                    header(
                        "Restore your wallet",
                        "This account has a wallet saved. Enter the PIN you chose to bring it to this phone."
                    )
                    walletLine(address)
                    pinFields(confirming: false)
                    action("Restore wallet") { await restore() }
                }

                if let problem { note(problem, icon: "exclamationmark.triangle.fill", tint: .orange) }
                if let done { note(done, icon: "checkmark.seal.fill", tint: RecourseColor.ledger) }
                assurance
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RecourseColor.night)
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: Pieces

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.recourse(22, .bold))
                .foregroundStyle(RecourseColor.nightText)
            Text(detail)
                .font(.recourse(13))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pinFields(confirming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if confirming {
                SecureField("Confirm PIN", text: $confirmation)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("At least \(WalletBackup.minimumPINLength) digits. A longer passphrase is stronger and is allowed.")
                    .font(.recourse(11))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
        }
    }

    private func action(_ title: String, _ work: @escaping () async -> Void) -> some View {
        Button {
            Task { await work() }
        } label: {
            if working {
                ProgressView().tint(.white).frame(maxWidth: .infinity).frame(height: 52)
            } else {
                Text(title)
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
        }
        .background(RecourseColor.ledger, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .buttonStyle(.plain)
        .disabled(working || pin.isEmpty)
        .opacity(working || pin.isEmpty ? 0.5 : 1)
    }

    private func walletLine(_ address: String) -> some View {
        // Named before the PIN is asked for, so someone can tell whether this is the
        // wallet they expected before they start typing secrets.
        detail("wallet.pass", "Wallet \(EthereumAddress(trusted: address).shortened)")
    }

    private func facts(address: String, updatedAt: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            walletLine(address)
            detail("clock.arrow.circlepath", "Saved \(updatedAt.prefix(10))")
        }
    }

    private var turnOff: some View {
        Button {
            Task { await disableRecovery() }
        } label: {
            Text("Turn off recovery")
                .font(.recourse(14, .semibold))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .buttonStyle(.plain)
        .disabled(working)
    }

    private var assurance: some View {
        VStack(alignment: .leading, spacing: 14) {
            detail("lock.shield", "Your key is encrypted on this phone before it leaves. Recourse stores the encrypted copy and never sees your PIN.")
            detail("exclamationmark.bubble", "Nobody can reset this PIN for you. Forgetting it means the backup cannot be opened.")
        }
        .padding(.top, 8)
    }

    private func detail(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .frame(width: 18)
            Text(text)
                .font(.recourse(12))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(text)
                .font(.recourse(12))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Behaviour

    /// Which of the three states this device is in is decided by two questions: does a
    /// backup exist for the account, and does a wallet exist on this phone.
    private func load() async {
        let stored = try? await withBackupAPI { api, token in
            try await api.fetch(accessToken: token)
        }
        // Deliberately not address(): that mints a wallet when none exists, which
        // would make the restore case unreachable and then make the restore itself
        // fail against the wallet it had just created.
        let hasLocalWallet = await environment.buyerSigner.hasWallet()

        if let stored {
            stage = hasLocalWallet
                ? .protected(address: stored.address, updatedAt: stored.updatedAt)
                : .restorable(address: stored.address)
        } else {
            stage = .unprotected
        }
    }

    private func enableRecovery() async {
        problem = nil
        done = nil
        guard pin == confirmation else {
            problem = "Those PINs do not match."
            return
        }
        focused = false
        working = true
        defer { working = false }

        do {
            let address = try await environment.buyerSigner.address().value
            // Exporting is gated behind the same authorizer as signing, so turning on
            // recovery asks for Face ID exactly as sending money does.
            let key = try await environment.buyerSigner.exportPrivateKey()
            let envelope = try WalletBackup.seal(privateKey: key, pin: pin, address: address)
            try await withBackupAPI { api, token in
                try await api.store(envelope: envelope, accessToken: token)
            }
            pin = ""
            confirmation = ""
            done = "Recovery is on. Sign in anywhere and unlock with your PIN."
            await load()
        } catch let error as WalletBackup.Failure {
            problem = error.message
        } catch {
            problem = "Recovery could not be turned on. Check your connection and try again."
        }
    }

    private func restore() async {
        problem = nil
        done = nil
        focused = false
        working = true
        defer { working = false }

        do {
            let stored = try await withBackupAPI { api, token in
                try await api.fetch(accessToken: token)
            }
            let key = try WalletBackup.open(stored.envelope, pin: pin)
            try await environment.buyerSigner.importPrivateKey(key)

            // Prove it before claiming success: the address the restored key derives
            // must be the one the backup named, or something is wrong and saying
            // "restored" would be a lie.
            let restored = try await environment.buyerSigner.address().value
            guard restored.lowercased() == stored.address.lowercased() else {
                try? await environment.buyerSigner.reset()
                problem = "The restored key did not match the saved wallet, so nothing was changed."
                return
            }

            pin = ""
            done = "Your wallet is back on this phone."
            await load()
        } catch let error as WalletBackup.Failure {
            problem = error.message
        } catch BuyerSignerError.walletAlreadyExists {
            problem = "This phone already has a wallet. Remove it first if you mean to replace it."
        } catch {
            problem = "That could not be restored. Check your connection and try again."
        }
    }

    private func disableRecovery() async {
        problem = nil
        done = nil
        working = true
        defer { working = false }
        do {
            try await withBackupAPI { api, token in
                try await api.remove(accessToken: token)
            }
            done = "Recovery is off. This wallet now exists only on this phone."
            await load()
        } catch {
            problem = "That could not be turned off. Check your connection and try again."
        }
    }

    @discardableResult
    private func withBackupAPI<T>(
        _ work: @escaping (any WalletBackupAPI, String) async throws -> T
    ) async throws -> T {
        let api = environment.makeWalletBackupAPIClient()
        return try await environment.accountSession.withAccessToken { token in
            try await work(api, token)
        }
    }
}
