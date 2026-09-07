import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Adding money from a chain that is not Arc, without connecting anything.
///
/// The person is shown a plain address and sends USDC to it from an exchange, or from
/// whatever wallet they already keep dollars in. There is nothing to connect and nothing
/// to sign, which is the whole point: asking somebody to connect a wallet turns a money
/// app back into a crypto app.
///
/// The address is a contract whose only power is paying this account on Arc, and where
/// it pays is part of the code it was built from, so the address itself is the promise.
struct BridgeDepositView: View {
    let environment: AppEnvironment

    @State private var addresses: [DepositAddress] = []
    @State private var loadFailed = false
    @State private var copied: String?

    var body: some View {
        ScrollView {
            content
        }
        .scrollIndicators(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("From another chain")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 20) {
            if let deposit = addresses.first {
                header(deposit)
                qr(for: deposit)
                addressBlock(deposit)
                steps(deposit)
            } else if loadFailed {
                unavailable
            } else {
                ProgressView().frame(height: 240)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
    }

    private func header(_ deposit: DepositAddress) -> some View {
        VStack(spacing: 6) {
            Text("Your \(deposit.chainName) address")
                .font(.recourse(17, .semibold))
                .foregroundStyle(RecourseColor.nightText)
            Text("Send USDC on \(deposit.chainName) here and it arrives in your Recourse balance.")
                .font(.recourse(12, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
    }

    private func qr(for deposit: DepositAddress) -> some View {
        Group {
            if let image = qrImage(for: deposit.address) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(RecourseColor.nightLine, lineWidth: 1)
                    }
            }
        }
    }

    private func addressBlock(_ deposit: DepositAddress) -> some View {
        VStack(spacing: 14) {
            Text(deposit.address)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(RecourseColor.nightText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)

            Button {
                UIPasteboard.general.string = deposit.address
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.snappy(duration: 0.2)) { copied = deposit.address }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.snappy(duration: 0.2)) { copied = nil }
                }
            } label: {
                let done = copied == deposit.address
                Label(done ? "Copied" : "Copy address", systemImage: done ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 26)
        }
    }

    /// The two things that lose people money here are sending the wrong token and
    /// sending on the wrong chain, so both are said plainly rather than in a footnote.
    private func steps(_ deposit: DepositAddress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            rule("USDC only, on \(deposit.chainName)", detail: "Anything else sent here cannot be recovered.", icon: "exclamationmark.triangle.fill", tint: RecourseColor.nightText)
            rule("At least \(deposit.minimum) USDC", detail: "Less than that waits here until you add more.", icon: "arrow.down.circle.fill", tint: RecourseColor.nightMuted)
            rule("Arrives in about a minute", detail: "Circle moves it to Arc. You are told when it lands.", icon: "clock.fill", tint: RecourseColor.nightMuted)
            rule("Nobody holds it but you", detail: "This address can only pay your Recourse account, and nothing else.", icon: "lock.fill", tint: RecourseColor.nightMuted)
        }
        .padding(16)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(RecourseColor.nightLine, lineWidth: 1)
        }
        .padding(.horizontal, 22)
    }

    private func rule(_ title: String, detail: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.recourse(13, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(detail)
                    .font(.recourse(11.5, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(RecourseColor.nightMuted)
            Text("Not open yet")
                .font(.recourse(15, .semibold))
                .foregroundStyle(RecourseColor.nightText)
            Text("Deposits from another chain are not switched on for this build. Add money on Arc for now.")
                .font(.recourse(12, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
        .padding(.top, 50)
    }

    @MainActor
    private func load() async {
        guard addresses.isEmpty else { return }
        do {
            let found = try await environment.accountSession.withAccessToken { token in
                try await environment.depositAPI.addresses(accessToken: token)
            }
            addresses = found
            loadFailed = found.isEmpty
        } catch {
            loadFailed = true
        }
    }

    private func qrImage(for content: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
