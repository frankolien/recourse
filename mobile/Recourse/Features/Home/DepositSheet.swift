import SwiftUI

/// The ways money gets in, including the ones that do not work yet.
///
/// Listing what is not ready is the point. The previous sheet showed an address
/// QR and nothing else, which quietly told anyone who does not already own USDC
/// that this app was not for them. A card row marked "Soon" answers the question
/// they actually have, and the honest reason it is not live is that a card
/// on ramp needs a registered business behind it, not that it was forgotten.
struct DepositSheet: View {
    let environment: AppEnvironment

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    methods
                    footnote
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(RecourseColor.night)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Deposit")
                .font(.recourse(28, .bold))
                .foregroundStyle(RecourseColor.nightText)
            Text("Add money to your Recourse wallet.")
                .font(.recourse(13, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
        }
    }

    private var methods: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEPOSIT WITH")
                .font(.recourse(11, .semibold))
                .kerning(1.1)
                .foregroundStyle(RecourseColor.nightMuted)

            NavigationLink {
                ReceiveAddressView(environment: environment)
            } label: {
                DepositRow(
                    icon: "qrcode",
                    title: "Crypto",
                    detail: "Receive USDC to your Recourse QR or address",
                    availability: .live
                )
            }
            .buttonStyle(.plain)

            // CCTP is Circle's own bridge and Arc supports it, so this is the next
            // one to become real rather than a wish. Addresses are already recorded
            // in deployments/arc-config.json.
            DepositRow(
                icon: "arrow.left.arrow.right",
                title: "From another chain",
                detail: "USDC from Base, Solana and more",
                availability: .soon
            )

            // Both of these need a registered business before any provider will
            // issue production keys, which is why they are dated by paperwork
            // rather than by engineering.
            DepositRow(
                icon: "creditcard",
                title: "Cash",
                detail: "Buy USDC with your bank card",
                availability: .soon
            )

            DepositRow(
                icon: "building.columns",
                title: "Bank transfer",
                detail: "Not open yet, use Crypto for now",
                availability: .soon
            )
        }
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RecourseColor.nightMuted)
                .frame(width: 16)
            // The second sentence is the part no other wallet can say. Everywhere
            // else you must hold a second token to move the first one.
            Text("Funds land as USDC on Arc. Fees are paid in USDC too, so you never need another token.")
                .font(.recourse(11, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum DepositAvailability {
    case live
    case soon
}

private struct DepositRow: View {
    let icon: String
    let title: String
    let detail: String
    let availability: DepositAvailability

    private var dimmed: Bool { availability == .soon }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(dimmed ? RecourseColor.nightMuted : RecourseColor.ledger)
                .frame(width: 46, height: 46)
                .background(
                    RecourseColor.night,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.recourse(16, .semibold))
                        .foregroundStyle(dimmed ? RecourseColor.nightMuted : RecourseColor.nightText)
                    if availability == .soon {
                        Text("Soon")
                            .font(.recourse(11, .medium))
                            .foregroundStyle(RecourseColor.nightMuted.opacity(0.8))
                    }
                }
                Text(detail)
                    .font(.recourse(12, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RecourseColor.nightMuted.opacity(dimmed ? 0.4 : 1))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RecourseColor.nightChip.opacity(dimmed ? 0.5 : 1),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(availability == .soon ? "\(title), coming soon. \(detail)" : "\(title). \(detail)")
    }
}
