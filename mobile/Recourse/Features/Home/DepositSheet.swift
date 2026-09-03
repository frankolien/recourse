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

    // Two across rather than four stacked. A stack reads as a ranked list and buries
    // the live option's siblings below the fold; a grid shows the whole shape of the
    // answer at once, which matters when three of the four are not open yet.
    private var methods: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEPOSIT WITH")
                .font(.recourse(11, .semibold))
                .kerning(1.1)
                .foregroundStyle(RecourseColor.nightMuted)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                spacing: 12
            ) {
                NavigationLink {
                    ReceiveAddressView(environment: environment)
                } label: {
                    DepositCard(
                        icon: "qrcode",
                        title: "Crypto",
                        detail: "To your QR or address",
                        availability: .live
                    )
                }
                .buttonStyle(.plain)

                // CCTP is Circle's own bridge and Arc supports it, so this is the next
                // one to become real rather than a wish. Addresses are already recorded
                // in deployments/arc-config.json.
                DepositCard(
                    icon: "arrow.left.arrow.right",
                    title: "Another chain",
                    detail: "Base, Solana and more",
                    availability: .soon
                )

                // Both of these need a registered business before any provider will
                // issue production keys, which is why they are dated by paperwork
                // rather than by engineering.
                DepositCard(
                    icon: "creditcard",
                    title: "Cash",
                    detail: "Buy with your card",
                    availability: .soon
                )

                DepositCard(
                    icon: "building.columns",
                    title: "Bank transfer",
                    detail: "Not open yet",
                    availability: .soon
                )
            }
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

private struct DepositCard: View {
    let icon: String
    let title: String
    let detail: String
    let availability: DepositAvailability

    private var dimmed: Bool { availability == .soon }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Filled for the one that works, hollow for the ones that do not. The
            // difference does the same job the word "Soon" does, a beat earlier.
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(dimmed ? RecourseColor.nightMuted : .white)
                .frame(width: 52, height: 52)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(dimmed ? RecourseColor.night : RecourseColor.ledger)
                        .overlay {
                            if dimmed {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(RecourseColor.nightLine, lineWidth: 1)
                            }
                        }
                }

            Spacer(minLength: 18)

            HStack(spacing: 6) {
                Text(title)
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(dimmed ? RecourseColor.nightMuted : RecourseColor.nightText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if availability == .soon {
                    Text("SOON")
                        .font(.recourse(8, .semibold))
                        .kerning(0.6)
                        .foregroundStyle(RecourseColor.nightMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RecourseColor.night, in: Capsule())
                }
            }
            .padding(.bottom, 3)

            Text(detail)
                .font(.recourse(12, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        // A floor rather than a fixed height: the grid equalises rows itself, and a
        // fixed one would clip the second line of a detail at larger type sizes.
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(
            RecourseColor.nightChip.opacity(dimmed ? 0.5 : 1),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(availability == .soon ? "\(title), coming soon. \(detail)" : "\(title). \(detail)")
    }
}
