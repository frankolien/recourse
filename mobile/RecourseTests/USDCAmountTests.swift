import XCTest
@testable import Recourse

final class USDCAmountTests: XCTestCase {
    func testParsesSixDecimalUSDCWithoutFloatingPoint() throws {
        let amount = try USDCAmount(decimalString: "24.000001")

        XCTAssertEqual(amount.baseUnits, 24_000_001)
        XCTAssertEqual(amount.formatted, "24.000001 USDC")
    }

    func testPadsAndTrimsFractionalDigits() throws {
        XCTAssertEqual(try USDCAmount(decimalString: "0.25").baseUnits, 250_000)
        XCTAssertEqual(USDCAmount(baseUnits: 1_240_000).formatted, "1.24 USDC")
        XCTAssertEqual(USDCAmount(baseUnits: 2_000_000).formatted, "2 USDC")
    }

    func testRejectsExcessPrecision() {
        XCTAssertThrowsError(try USDCAmount(decimalString: "1.0000001"))
    }

    func testRejectsZeroBaseUnitRequestAmount() {
        XCTAssertThrowsError(try USDCAmount(baseUnitString: "0"))
    }
}
