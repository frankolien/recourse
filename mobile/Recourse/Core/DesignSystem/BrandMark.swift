import SwiftUI

/// Small brand marks.
///
/// A deposit card that says "Base, Solana and more" is a sentence someone has to read;
/// three coins in the right colours is a fact they can see. Where a licence-clean vector
/// exists (USDC, Solana, Ethereum, all CC0) the real mark is used, unaltered. The rest
/// are drawn: the simplest shape that still reads as itself at 22 points.
enum BrandMark: Identifiable, Hashable {
    case usdc
    case arc
    case base
    case solana
    case ethereum
    case visa
    case mastercard
    case applePay
    case currency(String)

    var id: String {
        switch self {
        case .currency(let symbol): "currency-\(symbol)"
        default: String(describing: self)
        }
    }

    /// Wordmarks and card badges are wider than they are tall.
    var isWide: Bool {
        switch self {
        case .visa, .mastercard, .applePay: true
        default: false
        }
    }

    var accessibilityName: String {
        switch self {
        case .usdc: "USDC"
        case .arc: "Arc"
        case .base: "Base"
        case .solana: "Solana"
        case .ethereum: "Ethereum"
        case .visa: "Visa"
        case .mastercard: "Mastercard"
        case .applePay: "Apple Pay"
        case .currency(let symbol): symbol
        }
    }
}

struct BrandMarkView: View {
    let mark: BrandMark
    var height: CGFloat = 22

    private var width: CGFloat { mark.isWide ? height * 1.7 : height }

    var body: some View {
        Group {
            switch mark {
            case .usdc: usdc
            case .arc: arc
            case .base: base
            case .solana: solana
            case .ethereum: ethereum
            case .visa: visa
            case .mastercard: mastercard
            case .applePay: applePay
            case .currency(let symbol): currency(symbol)
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel(mark.accessibilityName)
    }

    // MARK: Coins

    // USDC, Solana and Ethereum are the real marks, from a CC0 set (see ICONS.md
    // beside the asset catalog). Unaltered, as their owners ask.
    private var usdc: some View {
        Image("USDCMark").resizable().scaledToFit()
    }

    private var arc: some View {
        ZStack {
            Circle().fill(RecourseColor.ink)
            Image("ArcMark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(height * 0.24)
        }
    }

    /// Base: the blue disc with the white notch entering from the left.
    private var base: some View {
        ZStack(alignment: .leading) {
            Circle().fill(Color(red: 0, green: 0.322, blue: 1))
            Rectangle()
                .fill(.white)
                .frame(width: height * 0.42, height: height * 0.14)
        }
        .clipShape(Circle())
    }

    private var solana: some View {
        Image("SolanaMark").resizable().scaledToFit()
    }

    private var ethereum: some View {
        Image("EthereumMark").resizable().scaledToFit()
    }

    private func currency(_ symbol: String) -> some View {
        ZStack {
            Circle().fill(RecourseColor.nightLine)
            Text(symbol)
                .font(.system(size: height * 0.5, weight: .bold, design: .rounded))
                .foregroundStyle(RecourseColor.nightText)
        }
    }

    // MARK: Cards

    private var visa: some View {
        ZStack {
            RoundedRectangle(cornerRadius: height * 0.22, style: .continuous).fill(.white)
            Text("VISA")
                .font(.system(size: height * 0.44, weight: .heavy, design: .default))
                .italic()
                .foregroundStyle(Color(red: 0.102, green: 0.122, blue: 0.443))
        }
    }

    private var mastercard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: height * 0.22, style: .continuous).fill(.white)
            HStack(spacing: -height * 0.22) {
                Circle().fill(Color(red: 0.922, green: 0, blue: 0.106))
                Circle().fill(Color(red: 0.969, green: 0.62, blue: 0.106)).opacity(0.92)
            }
            .padding(.vertical, height * 0.2)
        }
    }

    private var applePay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: height * 0.22, style: .continuous).fill(.black)
            HStack(spacing: 1.5) {
                Image(systemName: "apple.logo")
                    .font(.system(size: height * 0.42, weight: .medium))
                Text("Pay")
                    .font(.system(size: height * 0.44, weight: .medium))
            }
            .foregroundStyle(.white)
        }
    }
}

/// The marks in a row, each ringed in the card's own fill so they stay separate on any
/// background.
struct BrandMarkRow: View {
    let marks: [BrandMark]
    var height: CGFloat = 22
    var ring: Color = RecourseColor.nightChip

    var body: some View {
        HStack(spacing: 5) {
            ForEach(marks) { mark in
                BrandMarkView(mark: mark, height: height)
                    .overlay {
                        RoundedRectangle(cornerRadius: mark.isWide ? height * 0.22 : height / 2, style: .continuous)
                            .stroke(ring, lineWidth: 1)
                    }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
