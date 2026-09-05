import SwiftUI
import UIKit

/// The number pad a money app should own: big digits on the ground itself, no
/// system keyboard sliding over the amount, one decimal point, a backspace. The
/// bound text is the decimal string the amount types parse, never a number, so
/// "0." and trailing zeros survive typing exactly as the person typed them.
struct AmountKeypad: View {
    @Binding var text: String
    /// USDC and EURC carry six decimals; the pad stops at what the unit can hold.
    var maxFractionDigits: Int = 6

    private let rows: [[Key]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.point, .digit("0"), .delete],
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(rows[row]) { key in
                        Button {
                            press(key)
                        } label: {
                            key.label
                                .font(.system(size: 30, weight: .medium, design: .rounded))
                                .foregroundStyle(RecourseColor.nightText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 62)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key.accessibilityLabel)
                    }
                }
            }
        }
    }

    private func press(_ key: Key) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch key {
        case .delete:
            if !text.isEmpty { text.removeLast() }
        case .point:
            guard !text.contains(".") else { return }
            text = text.isEmpty ? "0." : text + "."
        case .digit(let digit):
            if let point = text.firstIndex(of: "."),
               text.distance(from: point, to: text.endIndex) > maxFractionDigits {
                return
            }
            text = text == "0" ? digit : text + digit
        }
    }

    private enum Key: Identifiable, Hashable {
        case digit(String)
        case point
        case delete

        var id: String {
            switch self {
            case .digit(let d): d
            case .point: "."
            case .delete: "delete"
            }
        }

        @ViewBuilder
        var label: some View {
            switch self {
            case .digit(let d): Text(d)
            case .point: Text(".")
            case .delete: Image(systemName: "delete.left.fill").font(.system(size: 22, weight: .semibold))
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .digit(let d): d
            case .point: "decimal point"
            case .delete: "delete"
            }
        }
    }
}
