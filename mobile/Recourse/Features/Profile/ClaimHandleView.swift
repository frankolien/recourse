import SwiftUI

/// Pick the name other people use to pay you.
///
/// The name points at whatever address this account currently signs with, and it is
/// re-pointed every time it is saved. That matters more than it looks: the wallet key
/// still lives on the device, so the address moves when the device does, and a handle
/// that kept an old address would send someone's money to a wallet nobody can open.
struct ClaimHandleView: View {
    let environment: AppEnvironment

    @State private var handleText = ""
    @State private var claimed: ResolvedHandle?
    @State private var address: String?
    @State private var saving = false
    @State private var problem: String?
    @State private var loading = true
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    field
                    if let problem {
                        message(problem, icon: "exclamationmark.triangle.fill", tint: .orange)
                    } else if let claimed, claimed.handle.lowercased() == typed.lowercased() {
                        message("People can pay you at @\(claimed.handle).", icon: "checkmark.seal.fill", tint: RecourseColor.ledger)
                    }
                    saveButton
                    explanation
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RecourseColor.night)
        .navigationTitle("Your name")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var typed: String {
        handleText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HANDLE")
                .font(.recourse(11, .semibold))
                .kerning(1.1)
                .foregroundStyle(RecourseColor.nightMuted)

            HStack(spacing: 4) {
                Text("@")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(RecourseColor.nightMuted)
                TextField("yourname", text: $handleText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(RecourseColor.nightText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { Task { await save() } }
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            if saving {
                ProgressView().tint(.white).frame(maxWidth: .infinity).frame(height: 52)
            } else {
                Text(claimed == nil ? "Claim this name" : "Save")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
        }
        .background(RecourseColor.ledger, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .buttonStyle(.plain)
        .disabled(saving || typed.isEmpty)
        .opacity(saving || typed.isEmpty ? 0.5 : 1)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 14) {
            detail(
                "at.circle.fill",
                "Anyone can send you USDC by typing @\(typed.isEmpty ? "yourname" : typed) instead of your address."
            )
            detail(
                "arrow.triangle.2.circlepath",
                "Your name points at this device's wallet. Save it again after you set up a new device, or payments will go to the old one."
            )
            if let address {
                detail("wallet.pass", "Currently pointing at \(EthereumAddress(trusted: address).shortened).")
            }
        }
        .padding(.top, 6)
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

    private func message(_ text: String, icon: String, tint: Color) -> some View {
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

    private func load() async {
        defer { loading = false }
        address = try? await environment.buyerSigner.address().value
        let api = environment.makeHandleAPIClient()
        let existing = try? await environment.accountSession.withAccessToken { token in
            try await api.myHandle(accessToken: token)
        }
        if let existing = existing ?? nil {
            claimed = existing
            handleText = existing.handle
        }
    }

    private func save() async {
        guard !typed.isEmpty else { return }
        focused = false
        problem = nil
        saving = true
        defer { saving = false }

        guard let address else {
            problem = "Your wallet is not ready yet. Try again in a moment."
            return
        }

        let api = environment.makeHandleAPIClient()
        do {
            claimed = try await environment.accountSession.withAccessToken { token in
                try await api.claim(handle: typed, address: address, accessToken: token)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch let error as HandleAPIError {
            problem = error.message
        } catch AccountSessionError.signedOut {
            problem = "Sign in again to claim a name."
        } catch {
            problem = "That could not be saved. Check your connection and try again."
        }
    }
}
