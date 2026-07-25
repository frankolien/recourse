import SwiftUI

// Dark greenish-black theme. `ink` is the primary TEXT color and is light;
// the old near-black survives as `inkSurface` for deliberately dark faces
// (cards, chips) that carry light text.
enum RecourseColor {
    static let ledger = Color(red: 0.07, green: 0.52, blue: 0.38)
    static let ledgerDeep = Color(red: 0.02, green: 0.39, blue: 0.29)
    static let mint = Color(red: 0.07, green: 0.10, blue: 0.085)
    static let canvas = Color(red: 0.043, green: 0.058, blue: 0.05)
    static let surface = Color(red: 0.043, green: 0.058, blue: 0.05)
    static let ink = Color(red: 0.93, green: 0.95, blue: 0.93)
    static let inkSurface = Color(red: 0.07, green: 0.09, blue: 0.08)
    static let muted = Color(red: 0.56, green: 0.62, blue: 0.59)
    static let line = Color(red: 0.15, green: 0.19, blue: 0.165)
    static let clay = Color(red: 0.088, green: 0.11, blue: 0.096)
    static let sky = Color(red: 0.088, green: 0.11, blue: 0.096)
    static let softGreen = Color(red: 0.07, green: 0.10, blue: 0.085)
}
