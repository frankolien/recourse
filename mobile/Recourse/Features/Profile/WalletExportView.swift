import SwiftUI
import UIKit

/// The way out. Shows this device's signing key so the wallet can be moved into
/// another app, or recovered if Recourse is gone.
///
/// Held back behind a deliberate reveal rather than shown on open: this screen is
/// the one place in the app where looking at it over someone's shoulder is enough
/// to take the money.
struct WalletExportView: View {
    var signer: (any BuyerSigner)?

    @State private var privateKey: String?
    @State private var error: String?
    @State private var revealing = false
    @State private var copied = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    point("key.horizontal.fill", "This is the key itself, not a backup code. Anyone who reads it can spend this wallet.")
                    point("square.and.arrow.up", "Import it into another wallet with \"Import private key\". It is not a 12 or 24 word recovery phrase and will not work where one is asked for.")
                    point("iphone.gen3", "Recourse never sends this anywhere. It is read from this device's keychain when you tap reveal.")
                }
                .padding(.vertical, 4)
            } header: {
                Text("Before you reveal it")
            }

            Section {
                if let shown = privateKey {
                    Text(shown)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.nightText)
                        .textSelection(.enabled)
                        .padding(.vertical, 6)

                    Button {
                        UIPasteboard.general.string = shown
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy key", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }

                    Button("Hide", role: .cancel) { privateKey = nil }
                } else {
                    Button {
                        Task { await reveal() }
                    } label: {
                        HStack {
                            Label("Reveal private key", systemImage: "eye")
                            Spacer()
                            if revealing { ProgressView() }
                        }
                    }
                    .disabled(revealing)
                }

                if let error {
                    Text(error)
                        .font(.recourse(12))
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Face ID is required. The key stays hidden until you ask for it and is cleared when you leave this screen.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Export wallet")
        .navigationBarTitleDisplayMode(.inline)
        // Clearing on background keeps the key out of the app switcher snapshot and
        // off the screen if the phone is handed over.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { privateKey = nil }
        }
        .onDisappear { privateKey = nil }
    }

    private func reveal() async {
        revealing = true
        error = nil
        defer { revealing = false }
        do {
            guard let signer else { throw BuyerSignerError.invalidAccount }
            let data = try await signer.exportPrivateKey()
            privateKey = "0x" + data.map { String(format: "%02x", $0) }.joined()
        } catch {
            self.error = "Could not read the key. Face ID may have been cancelled."
        }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .frame(width: 22)
            Text(text)
                .font(.recourse(12))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
