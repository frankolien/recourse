import XCTest
@testable import Recourse

/// The Earn screen's "earned" figures come from this phone's own records, so they
/// must say nothing until they know something.
final class EarnLedgerTests: XCTestCase {
    private let day: TimeInterval = 86_400

    func testEarnedSoFarIsThePositionLessWhatWentIn() {
        var ledger = EarnLedger()
        XCTAssertNil(ledger.earnedSoFar(position: USDCAmount(baseUnits: 5_000_000)), "no basis, no claim")

        ledger.noteDeposit(USDCAmount(baseUnits: 10_000_000))
        ledger.noteWithdrawal(USDCAmount(baseUnits: 2_000_000))
        XCTAssertEqual(ledger.earnedSoFar(position: USDCAmount(baseUnits: 8_400_000)), USDCAmount(baseUnits: 400_000))
        XCTAssertEqual(ledger.earnedSoFar(position: USDCAmount(baseUnits: 7_000_000)), USDCAmount(baseUnits: 0), "a loss is not negative earnings")
    }

    func testTheWeekAndTheRateNeedOldEnoughReadings() {
        var ledger = EarnLedger()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        ledger.record(price: 1.0, at: start)
        ledger.record(price: 1.0001, at: start.addingTimeInterval(3_600))
        XCTAssertEqual(ledger.prices.count, 1, "readings an hour apart collapse into one")

        XCTAssertNil(ledger.estimatedAPY(priceNow: 1.001, now: start.addingTimeInterval(12 * 3_600)))
        XCTAssertNil(ledger.earnedLastWeek(shares: 1_000_000, priceNow: 1.001, now: start.addingTimeInterval(3 * day)))

        let later = start.addingTimeInterval(8 * day)
        let apy = ledger.estimatedAPY(priceNow: 1.001, now: later)
        XCTAssertNotNil(apy)
        // 0.1 percent in eight days is roughly 4.7 percent a year.
        XCTAssertEqual(apy ?? 0, 0.0466, accuracy: 0.002)
        XCTAssertEqual(ledger.earnedLastWeek(shares: 1_000_000, priceNow: 1.001, now: later), USDCAmount(baseUnits: 1_000))
    }
}
