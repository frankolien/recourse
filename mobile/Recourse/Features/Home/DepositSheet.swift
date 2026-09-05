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
                VStack(alignment: .leading, spacing: 18) {
                    header
                    methods
                    footnote
                }
                .padding(.horizontal, 20)
                // Clear of the grabber. At ten points the title sat on the sheet's
                // edge and read as cut off rather than as the top of something.
                .padding(.top, 30)
                .padding(.bottom, 24)
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
                .font(.recourse(24, .bold))
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
                        detail: "USDC on Arc, to your QR or address",
                        marks: [.usdc, .arc],
                        availability: .live
                    )
                }
                .buttonStyle(DepositCardPress())

                // CCTP is Circle's own bridge and Arc supports it, so this is the next
                // one to become real rather than a wish. Addresses are already recorded
                // in deployments/arc-config.json.
                DepositCard(
                    icon: "arrow.left.arrow.right",
                    title: "Another chain",
                    detail: "USDC from Base, Solana or Ethereum",
                    marks: [.base, .solana, .ethereum],
                    availability: .soon
                )

                // Both of these need a registered business before any provider will
                // issue production keys, which is why they are dated by paperwork
                // rather than by engineering.
                DepositCard(
                    icon: "creditcard",
                    title: "Cash",
                    detail: "Buy with a card or Apple Pay",
                    marks: [.visa, .mastercard, .applePay],
                    availability: .soon
                )

                DepositCard(
                    icon: "building.columns",
                    title: "Bank transfer",
                    detail: "Dollars, euros or pounds from your bank",
                    marks: [.currency("$"), .currency("€"), .currency("£")],
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
    /// Spoken, not shown. The marks carry the meaning on screen; this is what VoiceOver
    /// says instead of reading out three logos.
    let detail: String
    let marks: [BrandMark]
    let availability: DepositAvailability

    private var dimmed: Bool { availability == .soon }
    private var fill: Color { RecourseColor.nightChip.opacity(dimmed ? 0.5 : 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                // Filled for the one that works, hollow for the ones that do not. The
                // difference does the same job the SOON badge does, a beat earlier.
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(dimmed ? RecourseColor.nightMuted : .white)
                    .frame(width: 40, height: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(dimmed ? RecourseColor.night : RecourseColor.ledger)
                            .overlay {
                                if dimmed {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(RecourseColor.nightLine, lineWidth: 1)
                                }
                            }
                    }

                Spacer(minLength: 6)

                if availability == .soon {
                    Text("SOON")
                        .font(.recourse(8, .semibold))
                        .kerning(0.6)
                        .foregroundStyle(RecourseColor.nightMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RecourseColor.night, in: Capsule())
                }
            }

            Spacer(minLength: 12)

            Text(title)
                .font(.recourse(14, .semibold))
                .foregroundStyle(dimmed ? RecourseColor.nightMuted : RecourseColor.nightText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            BrandMarkRow(marks: marks, height: 20, ring: fill)
                .opacity(dimmed ? 0.7 : 1)
                .padding(.top, 8)
        }
        .padding(13)
        // Small enough that both rows and the footnote sit inside the sheet's medium
        // detent; a floor rather than a fixed height so larger type still fits.
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            shape.fill(fill)
            if !dimmed {
                // The one that works is lit from its top-left corner, the way a card
                // lights under a finger, except it stays on.
                shape.fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.05), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 230
                    )
                )
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(availability == .soon ? "\(title), coming soon. \(detail)" : "\(title). \(detail)")
    }
}

/// The plain style's press look was the lift the live card now wears all the time,
/// so a press needs a different tell: the card settles under the finger.
private struct DepositCardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
