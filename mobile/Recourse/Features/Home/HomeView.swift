import SwiftUI

struct HomeView: View {
    let environment: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                balanceCard
                actionCard
                foundationNote
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(RecourseColor.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ARC TESTNET")
                    .recourseEyebrow()
                Spacer()
                Button {
                    environment.router.push(.account)
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(RecourseColor.ledgerDeep)
                }
                .accessibilityLabel("Account")
            }
            Text("Protected payments,\nin your pocket.")
                .font(RecourseTypography.display(size: 40))
                .foregroundStyle(RecourseColor.ink)
                .lineSpacing(-2)
            Text("Review the policy before you pay. Keep every receipt. Verify every outcome.")
                .foregroundStyle(RecourseColor.muted)
                .lineSpacing(4)
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Spending balance", systemImage: "shield.checkered")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("TESTNET")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text("Connect Arc to load")
                .font(RecourseTypography.display(size: 32))

            Text("USDC values will come from the 6-decimal ERC-20 interface.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecourseColor.ledgerDeep)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var actionCard: some View {
        ProtectedCard {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title2)
                    .foregroundStyle(RecourseColor.ledger)
                Text("Scan a protected checkout")
                    .font(.headline)
                    .foregroundStyle(RecourseColor.ink)
                Text("The QR decoder already rejects the wrong chain, escrow, amount, and order reference.")
                    .font(.subheadline)
                    .foregroundStyle(RecourseColor.muted)
            }
        }
    }

    private var foundationNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hammer")
                .foregroundStyle(RecourseColor.ledger)
            Text("Native foundation active. Wallet signing and live Arc reads are the next slice.")
                .font(.footnote)
                .foregroundStyle(RecourseColor.muted)
        }
    }
}
