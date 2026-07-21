import SwiftUI

struct ReceiptsFoundationView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Receipts")
                    .font(RecourseTypography.display(size: 42))
                    .foregroundStyle(RecourseColor.ink)

                ProtectedCard {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(RecourseColor.ledger)
                        Text("No receipts loaded yet")
                            .font(.headline)
                        Text("Buyer-filtered indexer reads and chain reconciliation land in M4.3.")
                            .font(.subheadline)
                            .foregroundStyle(RecourseColor.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            }
            .padding(20)
        }
        .background(RecourseColor.canvas)
    }
}
