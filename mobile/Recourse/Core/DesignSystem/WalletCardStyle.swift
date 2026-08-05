import SwiftUI

// The wallet card's face: the flat brand ink plus twelve art backgrounds the
// user picks from. The choice persists per device under one defaults key that
// Home and Earn both read. Text color is decided per face, dark ink on the
// light ones, white on the dark ones.
enum WalletCardStyle: String, CaseIterable, Identifiable, Sendable {
    static let defaultsKey = "recourse.walletcard.style"

    case ink
    case graphite
    case midnight
    case citrus
    case silver
    case piggy
    case bounty
    case wanderer
    case monarch
    case jackpot
    case prospector
    case gem
    case wolfpack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ink: "Ink"
        case .graphite: "Graphite"
        case .midnight: "Midnight"
        case .citrus: "Citrus"
        case .silver: "Silver"
        case .piggy: "Piggy"
        case .bounty: "Bounty"
        case .wanderer: "Wanderer"
        case .monarch: "Monarch"
        case .jackpot: "Jackpot"
        case .prospector: "Prospector"
        case .gem: "Gem"
        case .wolfpack: "Wolfpack"
        }
    }

    private var imageName: String? {
        switch self {
        case .ink: nil
        case .graphite: "wallet-card-1"
        case .midnight: "wallet-card-2"
        case .citrus: "wallet-card-3"
        case .silver: "wallet-card-4"
        case .piggy: "wallet-card-5"
        case .bounty: "wallet-card-6"
        case .wanderer: "wallet-card-7"
        case .monarch: "wallet-card-8"
        case .jackpot: "wallet-card-9"
        case .prospector: "wallet-card-10"
        case .gem: "wallet-card-11"
        case .wolfpack: "wallet-card-12"
        }
    }

    var prefersDarkText: Bool {
        switch self {
        case .citrus, .silver, .piggy, .bounty, .wanderer, .monarch, .jackpot, .prospector:
            true
        default:
            false
        }
    }

    var textPrimary: Color {
        prefersDarkText ? RecourseColor.ink : .white
    }

    var textSecondary: Color {
        prefersDarkText ? RecourseColor.ink.opacity(0.62) : .white.opacity(0.68)
    }

    var chipFill: Color {
        prefersDarkText ? RecourseColor.ink.opacity(0.08) : .white.opacity(0.12)
    }

    var chipStroke: Color {
        prefersDarkText ? RecourseColor.ink.opacity(0.14) : .white.opacity(0.16)
    }

    var border: Color {
        prefersDarkText ? RecourseColor.ink.opacity(0.12) : .white.opacity(0.1)
    }

    // The soft brand glow only reads on the flat ink face; art faces carry
    // themselves.
    var showsGlow: Bool { self == .ink }

    @ViewBuilder
    var face: some View {
        if let imageName {
            Image(imageName)
                .resizable()
                .scaledToFill()
        } else {
            RecourseColor.ink
        }
    }

    static func stored(rawValue: String) -> WalletCardStyle {
        WalletCardStyle(rawValue: rawValue) ?? .ink
    }
}

// Shared chrome for every wallet-grade card: padded face, continuous corners,
// hairline border, lifted shadow.
struct WalletCardSurface: ViewModifier {
    let style: WalletCardStyle

    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                style.face
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(style.border, lineWidth: 1)
            }
            .shadow(color: RecourseColor.ink.opacity(0.15), radius: 18, y: 10)
    }
}

// Picker sheet: every face rendered as a miniature card, current pick ringed.
struct WalletCardStylePicker: View {
    @Binding var selectedRawValue: String
    @Environment(\.dismiss) private var dismiss

    private var selected: WalletCardStyle {
        WalletCardStyle.stored(rawValue: selectedRawValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Card style")
                    .font(.recourse(20, .bold))
                    .foregroundStyle(RecourseColor.nightText)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    spacing: 14
                ) {
                    ForEach(WalletCardStyle.allCases) { style in
                        Button {
                            selectedRawValue = style.rawValue
                            UISelectionFeedbackGenerator().selectionChanged()
                            dismiss()
                        } label: {
                            miniCard(style)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(style.displayName) card style")
                    }
                }
            }
            .padding(22)
        }
        .background(RecourseColor.night)
    }

    private func miniCard(_ style: WalletCardStyle) -> some View {
        VStack(spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                style.face
                    .frame(height: 74)
                Text("Recourse")
                    .font(.recourse(9, .bold))
                    .foregroundStyle(style.textPrimary)
                    .padding(8)
            }
            .frame(height: 74)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected == style ? RecourseColor.ledger : style.border,
                        lineWidth: selected == style ? 2 : 1
                    )
            }

            HStack(spacing: 4) {
                if selected == style {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(RecourseColor.ledger)
                }
                Text(style.displayName)
                    .font(.recourse(11, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .lineLimit(1)
            }
        }
    }
}
