import SwiftUI
import UIKit

enum RecourseColor {
    static let ledger = Color(red: 0.02, green: 0.39, blue: 0.29)
    static let ledgerDeep = ledger
    static let mint = Color(red: 0.95, green: 0.96, blue: 0.95)
    static let canvas = Color(red: 0.98, green: 0.98, blue: 0.97)
    static let surface = Color.white
    static let ink = Color(red: 0.07, green: 0.09, blue: 0.08)
    static let muted = Color(red: 0.40, green: 0.42, blue: 0.41)
    static let line = Color(red: 0.89, green: 0.89, blue: 0.88)
    static let clay = Color(red: 0.95, green: 0.95, blue: 0.94)
    static let sky = Color(red: 0.95, green: 0.95, blue: 0.94)
    static let softGreen = Color(red: 0.96, green: 0.96, blue: 0.95)

    // In-app theme tokens. Onboarding keeps the static light palette above; the
    // screens past sign-in use these, which resolve per the user's chosen
    // appearance (Settings), greenish dark by default. Dark means FLAT: one
    // black ground, no section containers, chips only on tappable elements.
    static let night = adaptive(light: (1.0, 1.0, 1.0), dark: (0.027, 0.035, 0.03))
    static let nightChip = adaptive(light: (0.95, 0.95, 0.94), dark: (0.08, 0.10, 0.088))
    static let nightText = adaptive(light: (0.07, 0.09, 0.08), dark: (0.93, 0.95, 0.93))
    static let nightMuted = adaptive(light: (0.40, 0.42, 0.41), dark: (0.55, 0.60, 0.57))
    static let nightLine = adaptive(light: (0.89, 0.89, 0.88), dark: (0.13, 0.16, 0.14))

    // Cards that stay dark in BOTH themes (merchant hero): near-black raised a
    // step above the dark ground, the classic ink card on the light one.
    static let inkCard = Color(red: 0.07, green: 0.09, blue: 0.08)

    private static func adaptive(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}
