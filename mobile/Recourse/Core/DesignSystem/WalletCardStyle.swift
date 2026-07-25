import SwiftUI

// The wallet card's face. Two styles are photographic textures, the rest are
// drawn gradients, and the choice is the user's; it persists per device under
// a single defaults key that Home and Earn both read.
enum WalletCardStyle: String, CaseIterable, Identifiable, Sendable {
    static let defaultsKey = "recourse.walletcard.style"

    case ink
    case ledger
    case onyx
    case gold
    case mist
    case ember

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ink: "Ink"
        case .ledger: "Ledger"
        case .onyx: "Onyx"
        case .gold: "Gold"
        case .mist: "Mist"
        case .ember: "Ember"
        }
    }

    // Light faces carry dark text; everything on the card derives from these two.
    var prefersDarkText: Bool {
        switch self {
        case .gold, .mist: true
        default: false
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

    // The soft brand glow only reads on dark faces; on light ones it muddies.
    var showsGlow: Bool { !prefersDarkText }

    @ViewBuilder
    var face: some View {
        switch self {
        case .ink:
            RecourseColor.ink
        case .ledger:
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.22, blue: 0.17),
                    RecourseColor.ledger,
                    Color(red: 0.04, green: 0.47, blue: 0.35),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .onyx:
            Image("card-onyx")
                .resizable()
                .scaledToFill()
        case .gold:
            Image("card-gold")
                .resizable()
                .scaledToFill()
        case .mist:
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.94, blue: 0.93),
                    Color(red: 0.85, green: 0.87, blue: 0.86),
                    Color(red: 0.96, green: 0.96, blue: 0.95),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ember:
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.09, blue: 0.05),
                    Color(red: 0.55, green: 0.27, blue: 0.1),
                    Color(red: 0.79, green: 0.42, blue: 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
        VStack(alignment: .leading, spacing: 18) {
            Text("Card style")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(RecourseColor.ink)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
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

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private func miniCard(_ style: WalletCardStyle) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                style.face
                Text("Recourse")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(style.textPrimary)
                    .padding(10)
            }
            .frame(height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected == style ? RecourseColor.ledger : style.border,
                        lineWidth: selected == style ? 2 : 1
                    )
            }

            HStack(spacing: 5) {
                if selected == style {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RecourseColor.ledger)
                }
                Text(style.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RecourseColor.ink)
            }
        }
    }
}
