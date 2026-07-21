import Foundation

struct USDCAmount: Codable, Hashable, Sendable, Comparable {
    static let decimalPlaces = 6
    static let base: UInt64 = 1_000_000

    let baseUnits: UInt64

    init(baseUnits: UInt64) {
        self.baseUnits = baseUnits
    }

    init(baseUnitString: String) throws {
        guard let value = UInt64(baseUnitString), value > 0 else {
            throw ValidationError.invalidAmount
        }
        baseUnits = value
    }

    init(decimalString: String) throws {
        let pieces = decimalString.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2,
              let whole = UInt64(pieces[0]),
              pieces.allSatisfy({ $0.allSatisfy(\.isNumber) }) else {
            throw ValidationError.invalidAmount
        }

        let fractional = pieces.count == 2 ? String(pieces[1]) : ""
        guard fractional.count <= Self.decimalPlaces else {
            throw ValidationError.invalidAmount
        }

        let paddedFraction = fractional.padding(
            toLength: Self.decimalPlaces,
            withPad: "0",
            startingAt: 0
        )
        guard let fraction = UInt64(paddedFraction),
              whole <= (UInt64.max - fraction) / Self.base else {
            throw ValidationError.invalidAmount
        }

        baseUnits = whole * Self.base + fraction
    }

    static func < (lhs: USDCAmount, rhs: USDCAmount) -> Bool {
        lhs.baseUnits < rhs.baseUnits
    }

    var formatted: String {
        let whole = baseUnits / Self.base
        let fraction = baseUnits % Self.base
        guard fraction > 0 else { return "\(whole) USDC" }

        let fractionString = String(format: "%06llu", fraction)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return "\(whole).\(fractionString) USDC"
    }
}
