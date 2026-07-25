import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// The wallet's receiving side: this device's Arc address as a scannable QR.
// The QR carries the raw address so any wallet's scanner can read it.
struct ReceiveSheet: View {
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var address: String?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Receive USDC")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(RecourseColor.ink)

            if let address {
                if let qr = qrImage(for: address) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 190, height: 190)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(RecourseColor.line, lineWidth: 1)
                        }
                }

                Text(address)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(RecourseColor.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)

                Button {
                    UIPasteboard.general.string = address
                    copied = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label(copied ? "Copied" : "Copy address", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RecourseColor.ledger, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 26)
            } else {
                ProgressView()
                    .frame(height: 190)
            }

            Text("Arc Testnet only. USDC sent here lands in this device's wallet.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(RecourseColor.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .task {
            address = try? await environment.buyerSigner.address().value
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
