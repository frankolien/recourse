import SwiftUI

enum RecourseTypography {
    static func display(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
}

extension View {
    // Micro-labels read as structure, not action, so they stay neutral; green is
    // reserved for actions and positive state.
    func recourseEyebrow() -> some View {
        font(.system(size: 10, weight: .semibold))
            .tracking(1.25)
            .foregroundStyle(RecourseColor.muted)
    }
}
