import BigInt
import Foundation

/// EURC shares USDC's 6 decimals on Arc, but is a distinct unit and formatting it
/// through USDCAmount would put a dollar sign on euros.
struct EURCAmount: Equatable, Sendable, Codable {
    let baseUnits: UInt64

    init(baseUnits: UInt64) {
        self.baseUnits = baseUnits
    }

    init(baseUnits: BigUInt) {
        self.baseUnits = UInt64(baseUnits.description) ?? 0
    }

    /// Four places, for a quote where the last digits are the point.
    var formatted: String {
        String(format: "%.4f", Double(baseUnits) / 1_000_000)
    }

    /// Two places with the sign, for a balance.
    var money: String {
        String(format: "€%.2f", Double(baseUnits) / 1_000_000)
    }
}
