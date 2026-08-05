import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Proof-of-payment card rendered to an image for the share sheet. DM commerce
/// happens in chat threads, so the receipt is designed to go back into the
/// thread: a fixed light palette independent of the app theme, and a QR that
/// opens the public verifier so the other side can check the outcome without
/// installing anything.
struct PaymentShareCardView: View {
    let payment: DemoPayment

    private let ink = Color(red: 0.10, green: 0.12, blue: 0.11)
    private let muted = Color(red: 0.42, green: 0.47, blue: 0.45)
    private let ledger = Color(red: 5 / 255, green: 99 / 255, blue: 74 / 255)

    private var verifyURL: URL {
        AppConfiguration.webAppURL.appending(path: "verify/\(payment.id)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 7) {
                Image("LaunchMark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 21)
                Text("Recourse")
                    .font(.recourse(19, .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(ledger)
                Spacer()
                Text(payment.state.rawValue.uppercased())
                    .font(.recourse(10, .black))
                    .tracking(0.9)
                    .foregroundStyle(ledger)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(ledger.opacity(0.10), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(amountText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                Text("\(payment.merchant) · \(payment.item)")
                    .font(.recourse(13, .medium))
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }

            Divider()

            HStack(alignment: .top, spacing: 14) {
                if let qr = qrImage {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 74, height: 74)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Escrowed with protection on Arc")
                        .font(.recourse(13, .bold))
                        .foregroundStyle(ink)
                    Text("Payment #\(payment.id) · paid \(payment.date.formatted(date: .abbreviated, time: .omitted)) under \(payment.policyName)")
                        .font(.recourse(11, .medium))
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verifyURL.absoluteString)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ledger)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(24)
        .frame(width: 400, alignment: .leading)
        .background(.white)
    }

    private var amountText: String {
        let amount = Double(payment.amount.baseUnits) / Double(USDCAmount.base)
        return String(format: "$%.2f", amount)
    }

    private var qrImage: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(verifyURL.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

enum PaymentShareCard {
    /// The renderer runs on demand rather than per body evaluation: the card
    /// is a static artifact of the payment, not live UI.
    @MainActor
    static func render(for payment: DemoPayment) -> Image? {
        let renderer = ImageRenderer(content: PaymentShareCardView(payment: payment))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}

#if DEBUG
#Preview("Share card") {
    PaymentShareCardView(payment: DemoCatalog.payments[0])
}
#endif
