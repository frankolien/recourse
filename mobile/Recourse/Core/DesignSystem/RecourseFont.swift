import SwiftUI

/// Geist is the app's typeface, matching the web so both surfaces read as one
/// product. Text goes through this helper; SF Symbols keep .system fonts
/// because symbols only render from the system face.
extension Font {
    static func recourse(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = switch weight {
        case .bold, .heavy, .black: "Geist-Bold"
        case .semibold: "Geist-SemiBold"
        case .medium: "Geist-Medium"
        default: "Geist-Regular"
        }
        return .custom(name, size: size)
    }
}
