import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The address QR, one level down from Deposit rather than the whole of it.
///
/// It keeps the friendly verb up top and the raw address below, so any wallet's
/// scanner can still read it while the app never asks someone to think in 0x
/// strings. It is no longer the first thing a new user sees, because for anyone
/// who does not already hold USDC an address is a dead end.
struct ReceiveAddressView: View {
    let environment: AppEnvironment

    @State private var address: String?
    @State private var copied = false
    @State private var showsFaucet = false

    var body: some View {
        ScrollView {
            content
        }
        .scrollIndicators(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Receive USDC")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            address = try? await environment.buyerSigner.address().value
        }
        .sheet(isPresented: $showsFaucet) {
            SafariWebView(url: URL(string: "https://faucet.circle.com")!)
                .ignoresSafeArea()
        }
    }

    private var content: some View {
        VStack(spacing: 20) {
            Text("Send USDC to this address and it lands in your balance.")
                .font(.recourse(12, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

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
                                .stroke(RecourseColor.nightLine, lineWidth: 1)
                        }
                }

                Text(address)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(RecourseColor.nightText)
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

                // Circle's official faucet funds any Arc testnet address, so a
                // fresh install can self-serve from zero. Copying first saves a
                // hop: the faucet form's only input is the address already here.
                Button {
                    UIPasteboard.general.string = address
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showsFaucet = true
                } label: {
                    Label("Get free test USDC", systemImage: "drop.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RecourseColor.nightChip, in: Capsule())
                        .overlay { Capsule().stroke(RecourseColor.nightLine, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 26)

                Text("Opens Circle's faucet with your address copied. 20 USDC every 2 hours.")
                    .font(.recourse(11, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            } else {
                ProgressView()
                    .frame(height: 190)
            }

            Text("Arc Testnet only. Money added here follows this device.")
                .font(.recourse(11, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding(.top, 16)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
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
