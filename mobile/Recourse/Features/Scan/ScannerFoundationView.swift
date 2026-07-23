import SwiftUI
import VisionKit

struct ScannerFoundationView: View {
    let configuration: AppConfiguration
    let onScan: (PaymentRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isScanning = false
    @State private var scanLineOffset: CGFloat = -110
    @State private var manualCode = ""
    @State private var scanError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if DataScannerViewController.isSupported,
               DataScannerViewController.isAvailable {
                LiveQRScanner(onPayload: handleScannedPayload)
                    .ignoresSafeArea()
            } else {
                cameraBackdrop
            }
            VStack(spacing: 0) {
                topBar
                Spacer()
                scannerFrame
                Spacer()
                bottomPanel
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: true)) {
                scanLineOffset = 110
            }
        }
    }

    private var cameraBackdrop: some View {
        ZStack {
            Color(red: 0.04, green: 0.07, blue: 0.06)
            VStack(spacing: 0) {
                Color.black.opacity(0.2)
                Rectangle()
                    .fill(Color(red: 0.09, green: 0.16, blue: 0.14))
                    .overlay {
                        Image(systemName: "storefront.fill")
                            .font(.system(size: 180, weight: .thin))
                            .foregroundStyle(.white.opacity(0.035))
                    }
                Color.black.opacity(0.35)
            }
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            RecourseGlassIconButton(systemName: "xmark", accessibilityLabel: "Close") { dismiss() }
            Spacer()
            VStack(spacing: 2) {
                Text("PROTECTED CHECKOUT")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.4)
                Text("Arc Testnet")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            RecourseGlassIconButton(systemName: "bolt.fill", accessibilityLabel: "Flash") {}
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var scannerFrame: some View {
        VStack(spacing: 26) {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(0.15))
                    .frame(width: 280, height: 280)
                scannerCorners
                Rectangle()
                    .fill(RecourseColor.ledger)
                    .frame(width: 238, height: 2)
                    .shadow(color: RecourseColor.ledger, radius: 8)
                    .offset(y: scanLineOffset)
            }
            VStack(spacing: 7) {
                Text(isScanning ? "Checkout found" : "Scan the merchant QR")
                    .font(.system(size: 22, weight: .bold))
                Text(scannerMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(scanError == nil ? .white.opacity(0.68) : Color.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
            }
        }
        .foregroundStyle(.white)
    }

    private var scannerCorners: some View {
        ZStack {
            ForEach(0..<4) { index in
                UnevenRoundedRectangle(
                    topLeadingRadius: index == 0 ? 26 : 0,
                    bottomLeadingRadius: index == 3 ? 26 : 0,
                    bottomTrailingRadius: index == 2 ? 26 : 0,
                    topTrailingRadius: index == 1 ? 26 : 0
                )
                .trim(from: 0, to: 0.18)
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 260, height: 260)
                .rotationEffect(.degrees(Double(index) * 90))
            }
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            Button {
                openRequest(DemoCatalog.checkoutRequest(configuration: configuration))
            } label: {
                Label("Try demo checkout", systemImage: "qrcode")
            }
            .buttonStyle(RecoursePrimaryButtonStyle())

            HStack(spacing: 12) {
                Image(systemName: "number")
                    .foregroundStyle(RecourseColor.ledger)
                TextField("Enter payment code", text: $manualCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .foregroundStyle(RecourseColor.ink)
                    .onSubmit(openManualCode)
                Button("Open") {
                    openManualCode()
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(RecourseColor.ledger)
                .disabled(manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 17))

            Label("Only QR codes for this Arc escrow are accepted", systemImage: "lock.shield")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(20)
        .padding(.bottom, 14)
        .background(Color.black.opacity(0.72))
    }

    private var scannerMessage: String {
        if let scanError {
            return scanError
        }
        return isScanning
            ? "Checking chain, escrow, amount, and policy…"
            : "You will review every protection term before money moves."
    }

    private func handleScannedPayload(_ payload: String) {
        guard !isScanning else { return }
        decodeAndOpen(payload)
    }

    private func openManualCode() {
        decodeAndOpen(manualCode)
    }

    private func decodeAndOpen(_ value: String) {
        do {
            let payload = try paymentPayload(from: value)
            let request = try PaymentRequestDecoder(configuration: configuration)
                .decode(base64URL: payload)
            openRequest(request)
        } catch {
            isScanning = false
            scanError = "This is not a valid Recourse checkout for Arc Testnet."
        }
    }

    private func openRequest(_ request: PaymentRequest) {
        scanError = nil
        isScanning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            onScan(request)
        }
    }

    private func paymentPayload(from value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.invalidPaymentRequest }

        if let components = URLComponents(string: trimmed),
           components.scheme != nil {
            let names = ["request", "payload", "code"]
            if let payload = components.queryItems?
                .first(where: { names.contains($0.name.lowercased()) })?
                .value,
               !payload.isEmpty {
                return payload
            }
        }
        return trimmed
    }
}

private struct LiveQRScanner: UIViewControllerRepresentable {
    let onPayload: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(
        _ uiViewController: DataScannerViewController,
        context: Context
    ) {}

    static func dismantleUIViewController(
        _ uiViewController: DataScannerViewController,
        coordinator: Coordinator
    ) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onPayload: (String) -> Void
        private var lastPayload: String?

        init(onPayload: @escaping (String) -> Void) {
            self.onPayload = onPayload
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard case .barcode(let barcode) = addedItems.first,
                  let payload = barcode.payloadStringValue,
                  payload != lastPayload else {
                return
            }
            lastPayload = payload
            onPayload(payload)
        }
    }
}

#Preview("Protected scanner") {
    ScannerFoundationView(configuration: .live) { _ in }
}
