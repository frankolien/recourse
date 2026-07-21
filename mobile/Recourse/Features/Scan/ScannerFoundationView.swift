import SwiftUI

struct ScannerFoundationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                RecourseColor.ledgerDeep.ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 92, weight: .thin))
                        .foregroundStyle(.white)

                    VStack(spacing: 10) {
                        Text("Scan to pay safely")
                            .font(RecourseTypography.display(size: 34))
                        Text("Camera capture arrives with the live checkout flow in M4.2.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)

                    Spacer()
                }
                .padding(28)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
