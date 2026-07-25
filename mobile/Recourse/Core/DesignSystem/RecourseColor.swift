import SwiftUI

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

    // In-app dark theme. Onboarding deliberately keeps the light palette above;
    // these tokens are used only past the sign-in boundary. The ground is one
    // flat greenish black; content sits directly on it, no section containers.
    static let night = Color(red: 0.027, green: 0.035, blue: 0.03)
    static let nightChip = Color(red: 0.08, green: 0.10, blue: 0.088)
    static let nightText = Color(red: 0.93, green: 0.95, blue: 0.93)
    static let nightMuted = Color(red: 0.55, green: 0.60, blue: 0.57)
    static let nightLine = Color(red: 0.13, green: 0.16, blue: 0.14)
}
