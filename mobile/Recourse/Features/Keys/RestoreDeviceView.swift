import SwiftUI

/// Moves the account's Device Key onto this phone after the old one is gone.
///
/// The old phone's key cannot be copied, so this makes a new one here and swaps it
/// into the account. That swap needs two of three, and the one missing is the Device
/// Key itself, so the pair is the Cloud Key on this phone and the Recovery Key, which
/// the emailed code releases. Three steps, shown as three bars: start, the code,
/// finish.
struct RestoreDeviceView: View {
    let environment: AppEnvironment

    private enum Stage: Equatable {
        case start
        case code(sentTo: String)
        case finish(grantID: String)
        case working
        case done(DeviceRotationOutcome)
        case created(safe: String)

        var step: Int {
            switch self {
            case .start: 1
            case .code: 2
            case .finish, .working, .done, .created: 3
            }
        }
    }

    @State private var stage: Stage = .start
    @State private var code = ""
    @State private var problem: String?
    @State private var showsWarning = false
    @State private var balance: USDCAmount?
    /// The Cloud Key this phone holds, if it is the account's. Nil means it is
    /// missing or a stray, and the way forward is the PIN backup, not the code.
    @State private var cloudAddress: String?
    /// Whatever Cloud Key this phone holds, the account's or not: the one a new
    /// wallet would be made with.
    @State private var localCloud: String?
    @State private var checkedCloud = false
    /// The second door: no PIN, or no backup, so the old wallet is given up and a
    /// new one made with the keys on this phone.
    @State private var startingFresh = false
    @FocusState private var codeFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var store: SmartAccountStore { environment.smartAccounts }
    private var email: String { environment.accountSession.account?.email ?? "your email" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch stage {
                    case .start:
                        start
                    case .code(let sentTo):
                        confirmEmail(sentTo: sentTo)
                    case .finish, .working:
                        finish
                    case .done(let outcome):
                        done(outcome)
                    case .created(let safe):
                        created(safe)
                    }
                    if let problem {
                        Text(problem)
                            .font(.recourse(13, .medium))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 44)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RecourseColor.night.ignoresSafeArea())
        .overlay(alignment: .bottom) { footer }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadFacts() }
        .sheet(isPresented: $showsWarning) { warning }
    }

    // MARK: Chrome

    private var progress: some View {
        HStack(spacing: 10) {
            ForEach(1 ... 3, id: \.self) { index in
                Capsule()
                    .fill(index <= stage.step ? RecourseColor.ledger : RecourseColor.nightChip)
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.25), value: stage.step)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.recourse(42, .bold))
            .foregroundStyle(RecourseColor.nightText)
            .lineSpacing(-2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func lead(_ text: String) -> some View {
        Text(text)
            .font(.recourse(19))
            .foregroundStyle(RecourseColor.nightMuted)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func primary(_ label: String, working: Bool = false, enabled: Bool = true, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                if working { ProgressView().tint(.white) }
                Text(working ? "Recovering" : label)
            }
            .font(.recourse(17, .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RecourseColor.ledger, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || working)
        .opacity(enabled ? 1 : 0.5)
    }

    private func secondary(_ label: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(.recourse(17, .semibold))
                .foregroundStyle(RecourseColor.nightText)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RecourseColor.nightChip, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var footer: some View {
        Group {
            switch stage {
            case .start:
                if checkedCloud, cloudAddress == nil {
                    // Two doors: the PIN backup brings the account's key back; without
                    // a PIN the old wallet is given up and a new one made here.
                    VStack(spacing: 10) {
                        NavigationLink {
                            WalletRecoveryView(environment: environment)
                        } label: {
                            Text("Bring back the Cloud Key")
                                .font(.recourse(17, .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(RecourseColor.ledger, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        secondary("Start a new wallet instead") {
                            startingFresh = true
                            showsWarning = true
                        }
                    }
                } else {
                    primary("Start Recovery", enabled: checkedCloud) {
                        startingFresh = false
                        showsWarning = true
                    }
                }
            case .code:
                primary("Confirm", enabled: code.count == 6) { Task { await verify() } }
            case .finish:
                primary(startingFresh ? "Create new wallet" : "Finish Recovery") { Task { await finishRecovery() } }
            case .working:
                primary("Finish Recovery", working: true) {}
            case .done, .created:
                primary("Done") { dismiss() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .background(
            LinearGradient(colors: [RecourseColor.night.opacity(0), RecourseColor.night], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
        )
    }

    // MARK: Step 1

    private var start: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Start your\nrecovery\nprocess")
            lead("Your Recourse account,\nwith your Cloud Key")
                .padding(.top, 22)

            accountCard
                .padding(.top, 26)

            HStack(spacing: 10) {
                keyTile("Device", detail: "Recovering...", glyph: "faceid", dim: true)
                keyTile("Cloud", detail: cloudAddress.map(shortened) ?? (checkedCloud ? "Not on this phone" : "Checking"), glyph: "icloud.fill", dim: true)
                keyTile("Recovery", detail: email, glyph: "envelope.fill", dim: true)
            }
            .padding(.top, 10)
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(store.record.map { shortened($0.safe) } ?? "Your account")
                    .font(.recourse(20, .medium))
                    .foregroundStyle(RecourseColor.nightText)
                Spacer()
                Text("Recourse account")
                    .font(.recourse(17))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            Text(balance.map { String(format: "$%.2f", Double($0.baseUnits) / Double(USDCAmount.base)) } ?? "$")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(RecourseColor.nightText)
                .opacity(balance == nil ? 0.35 : 1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(RecourseColor.nightLine, lineWidth: 1))
    }

    private func keyTile(_ name: String, detail: String, glyph: String, dim: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.recourse(17, .semibold))
                .foregroundStyle(RecourseColor.nightText)
            Text(detail)
                .font(.recourse(13))
                .foregroundStyle(RecourseColor.nightMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 24)
            HStack {
                Spacer()
                Image(systemName: glyph)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(RecourseColor.nightMuted.opacity(dim ? 0.7 : 1))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recovery warning")
                    .font(.recourse(22, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Spacer()
                Button { showsWarning = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            Text(startingFresh
                ? "Your old wallet stays on Arc with whatever it holds, and no key can reach it any more. This account gets a new wallet with the keys on this phone."
                : "If you begin and finish your recovery, your Recourse account will no longer be available on the previous phone.")
                .font(.recourse(17))
                .foregroundStyle(RecourseColor.nightMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            primary("Agree and Continue") {
                showsWarning = false
                Task { await sendCode() }
            }
            .padding(.top, 8)
        }
        .padding(24)
        .padding(.bottom, 8)
        .background(RecourseColor.night)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(36)
    }

    // MARK: Step 2

    private func confirmEmail(sentTo: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                stage = .start
                problem = nil
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(RecourseColor.nightText)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .padding(.top, -30)
            .padding(.bottom, 10)

            title("Confirm email")
            lead("The code has been sent to")
                .padding(.top, 22)
            Text(email)
                .font(.recourse(26, .medium))
                .foregroundStyle(RecourseColor.nightText)
                .padding(.top, 6)
            lead("Check your inbox and paste\nthe code from the email below")
                .padding(.top, 26)

            codeBoxes
                .padding(.top, 22)

            HStack {
                Spacer()
                Button {
                    let pasted = (UIPasteboard.general.string ?? "").filter(\.isNumber)
                    if pasted.count >= 6 { code = String(pasted.prefix(6)) }
                } label: {
                    Text("Paste")
                        .font(.recourse(17, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                        .padding(.horizontal, 30)
                        .frame(height: 50)
                        .background(RecourseColor.nightChip, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 20)

            HStack {
                Spacer()
                Button("Send another code") { Task { await sendCode() } }
                    .font(.recourse(14, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                Spacer()
            }
            .padding(.top, 18)
        }
        .onChange(of: code) { _, value in
            let digits = String(value.filter(\.isNumber).prefix(6))
            if digits != value { code = digits }
            if digits.count == 6 { Task { await verify() } }
        }
    }

    // Six boxes over one hidden field: the field takes the keyboard and the paste,
    // the boxes show what it holds.
    private var codeBoxes: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($codeFocused)
                .opacity(0.02)
                .frame(height: 1)
            HStack(spacing: 10) {
                ForEach(0 ..< 6, id: \.self) { index in
                    let digits = Array(code)
                    Text(index < digits.count ? String(digits[index]) : "")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(RecourseColor.nightText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 74)
                        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            if index >= digits.count {
                                Rectangle().fill(RecourseColor.nightMuted.opacity(0.5)).frame(width: 12, height: 2)
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { codeFocused = true }
        }
        .onAppear { codeFocused = true }
    }

    // MARK: Step 3

    private var finish: some View {
        VStack(alignment: .leading, spacing: 0) {
            title(startingFresh ? "Start a new\nwallet" : "Finish Recovery")
            lead(startingFresh
                ? "Your new keys are on this phone. Check them below and confirm."
                : "Your Recourse account is ready to be recovered. Check your keys below and confirm.")
                .padding(.top, 22)
            VStack(spacing: 12) {
                keyRow("Device", detail: "This iPhone", glyph: "faceid")
                keyRow("Cloud", detail: (startingFresh ? localCloud : cloudAddress).map(shortened) ?? "Cloud Key", glyph: "icloud.fill")
                keyRow("Recovery", detail: email, glyph: "envelope.fill")
            }
            .padding(.top, 28)
        }
    }

    private func created(_ safe: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Your new wallet\nis ready")
            lead("Made on Arc with the keys on this phone. The old one is closed to this account.")
                .padding(.top, 22)
            Text(safe)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(RecourseColor.nightMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 20)
        }
    }

    private func keyRow(_ name: String, detail: String, glyph: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.recourse(22, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(detail)
                    .font(.recourse(17))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: glyph)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(RecourseColor.nightMuted)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func done(_ outcome: DeviceRotationOutcome) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title("This phone is\nyour Device Key")
            lead("The swap went through on Arc. Both keys sign your payments from here on.")
                .padding(.top, 22)
            Text(outcome.txHash)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(RecourseColor.nightMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 20)
        }
    }

    // MARK: Actions

    private func loadFacts() async {
        let owner = store.record?.cloudOwner
        let local = try? await environment.switchableSigner.cloud.address().value
        localCloud = local
        if let local, let owner, local.lowercased() == owner.lowercased() {
            cloudAddress = local
        } else {
            cloudAddress = nil
        }
        checkedCloud = true
        if let safe = store.record?.safe, let gateway = try? environment.makeContractGateway() {
            balance = try? await gateway.usdcBalance(of: EthereumAddress(trusted: safe))
        }
    }

    private func sendCode() async {
        problem = nil
        do {
            let issued = try await store.requestRecoveryCode()
            code = ""
            stage = .code(sentTo: issued.sentTo)
        } catch {
            problem = SmartAccountStore.describe(error)
        }
    }

    private func verify() async {
        guard case .code = stage else { return }
        problem = nil
        let entered = code.trimmingCharacters(in: .whitespaces)
        guard entered.count == 6 else {
            problem = "Enter the six digits from the email."
            return
        }
        do {
            let grant = try await store.verifyRecoveryCode(entered)
            codeFocused = false
            stage = .finish(grantID: grant.grantId)
        } catch {
            problem = SmartAccountStore.describe(error)
        }
    }

    private func finishRecovery() async {
        guard case .finish(let grantID) = stage else { return }
        problem = nil
        stage = .working
        do {
            if startingFresh {
                let record = try await store.startOver(grantID: grantID)
                stage = .created(safe: record.safe)
                return
            }
            let outcome = try await store.restoreDevice(grantID: grantID)
            stage = .done(outcome)
        } catch {
            problem = SmartAccountStore.describe(error)
            stage = .finish(grantID: grantID)
        }
    }

    private func shortened(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}
