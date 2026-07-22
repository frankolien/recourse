import SwiftUI

enum RecourseTypography {
    static func display(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
}

extension View {
    func recourseEyebrow() -> some View {
        font(.system(size: 12, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(RecourseColor.ledger)
    }
}
