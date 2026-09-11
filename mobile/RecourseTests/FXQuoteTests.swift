import XCTest
@preconcurrency import BigInt
@testable import Recourse

/// The Swift half of a three way agreement. The same inputs are asserted in
/// engine/test/fx.test.ts and contracts/test/MiniAmm.t.sol, because a wallet that
/// quoted differently from the engine or the pool would show a user one number and
/// hand them another.
final class FXQuoteTests: XCTestCase {
    // The live Arc pool, seeded 2026-08-19.
    private let poolUSDC = BigUInt(23_070_000)
    private let poolEURC = BigUInt(20_000_000)
    // EUR/USD 1.1534 on 2026-08-13, expressed as EURC per USDC.
    private let reference = 0.867

    func testCurveMatchesTheOtherImplementations() throws {
        // Pinned identically in the TypeScript and Solidity suites.
        let out = try FX.amountOut(
            amountIn: BigUInt(1_000_000),
            reserveIn: BigUInt(1_000_000_000),
            reserveOut: BigUInt(2_000_000_000)
        )
        XCTAssertEqual(out, BigUInt(1_992_013))
    }

    func testQuoteMatchesTheLivePool() throws {
        // The exact fill observed on Arc: 0.40 USDC returned 339855 EURC.
        let out = try FX.amountOut(amountIn: BigUInt(400_000), reserveIn: poolUSDC, reserveOut: poolEURC)
        XCTAssertEqual(out, BigUInt(339_855))
    }

    func testFlooringNeverQuotesMoreThanThePoolPays() throws {
        // Rounding up here would promise output the pool cannot cover.
        let out = try FX.amountOut(amountIn: BigUInt(7), reserveIn: BigUInt(1_000_003), reserveOut: BigUInt(999_997))
        XCTAssertEqual(out, BigUInt(6))
    }

    func testEmptyPoolIsRefusedRatherThanDividedByZero() {
        XCTAssertThrowsError(try FX.amountOut(amountIn: 1, reserveIn: 0, reserveOut: 1))
        XCTAssertThrowsError(try FX.amountOut(amountIn: 1, reserveIn: 1, reserveOut: 0))
        XCTAssertThrowsError(try FX.amountOut(amountIn: 0, reserveIn: 1, reserveOut: 1))
    }

    func testSlippageFloorsTheOutput() throws {
        XCTAssertEqual(try FX.applySlippage(BigUInt(10_000), slippageBps: 50), BigUInt(9_950))
        XCTAssertEqual(try FX.applySlippage(BigUInt(10_000), slippageBps: 0), BigUInt(10_000))
        XCTAssertThrowsError(try FX.applySlippage(BigUInt(1), slippageBps: 10_001))
        XCTAssertThrowsError(try FX.applySlippage(BigUInt(1), slippageBps: -1))
    }

    // The size the guard allows against the live pool, matching what
    // ops/seed-pool.sh reported when it seeded.
    func testGuardPassesTheLargestSaneTrade() throws {
        let out = try FX.amountOut(amountIn: BigUInt(400_000), reserveIn: poolUSDC, reserveOut: poolEURC)
        let quote = try FX.quote(
            amountIn: BigUInt(400_000), amountOut: out,
            decimalsIn: 6, decimalsOut: 6, referencePrice: reference
        )
        XCTAssertEqual(quote.deviationBps, 200)
        XCTAssertNoThrow(try FX.assertSane(quote))
    }

    func testGuardRefusesATradeTooLargeForTheDepth() throws {
        let out = try FX.amountOut(amountIn: BigUInt(1_000_000), reserveIn: poolUSDC, reserveOut: poolEURC)
        let quote = try FX.quote(
            amountIn: BigUInt(1_000_000), amountOut: out,
            decimalsIn: 6, decimalsOut: 6, referencePrice: reference
        )
        XCTAssertEqual(quote.deviationBps, 444)
        XCTAssertThrowsError(try FX.assertSane(quote)) { error in
            guard case FXQuoteError.offMarket(let bps) = error else {
                return XCTFail("expected offMarket, got \(error)")
            }
            XCTAssertEqual(bps, 444)
        }
    }

    /// The reason the guard exists. These are the real reserves of the only
    /// stablecoin pool on Arc, measured 2026-08-13.
    func testGuardRefusesTheLiveArcSwapPool() throws {
        let out = try FX.amountOut(
            amountIn: BigUInt(100_000_000),
            reserveIn: BigUInt(236_062_365),
            reserveOut: BigUInt(92_110_704)
        )
        let quote = try FX.quote(
            amountIn: BigUInt(100_000_000), amountOut: out,
            decimalsIn: 6, decimalsOut: 6, referencePrice: reference
        )
        // 100 USDC quotes about 27 EURC where the reference implies 87.
        XCTAssertLessThan(quote.amountOut, BigUInt(30_000_000))
        XCTAssertGreaterThan(quote.deviationBps ?? 0, 6_000)
        XCTAssertThrowsError(try FX.assertSane(quote))
    }

    func testAVenueBetterThanTheReferenceIsNotBlocked() throws {
        let quote = try FX.quote(
            amountIn: BigUInt(1_000_000), amountOut: BigUInt(1_000_000),
            decimalsIn: 6, decimalsOut: 6, referencePrice: 0.867
        )
        XCTAssertLessThan(quote.deviationBps ?? 0, 0)
        XCTAssertNoThrow(try FX.assertSane(quote))
    }

    func testQuoteWithNoOutputIsRefused() {
        XCTAssertThrowsError(try FX.quote(amountIn: 1_000, amountOut: 0, decimalsIn: 6, decimalsOut: 6))
    }

    // MARK: The ceiling a thin pool imposes

    /// The pool this app seeded on Arc: 23.072357 USDC against 20 EURC.
    private let seededPool = (usdc: BigUInt(23_072_357), eurc: BigUInt(20_000_000))

    func testCeilingMatchesTheSeededPool() {
        let cap = FX.maxAmountIn(
            reserveIn: seededPool.usdc, reserveOut: seededPool.eurc,
            decimalsIn: 6, decimalsOut: 6, referencePrice: 0.867
        )
        // 0.397044 USDC, the exact boundary of the 200 bps guard on this pool.
        // Pinned because this number is shown to a user as a promise.
        XCTAssertEqual(cap, BigUInt(397_044))
    }

    func testEveryCeilingIsItselfQuotable() throws {
        // The guarantee the chip depends on. An amount offered as the maximum must
        // survive the same check the next quote runs, or tapping it would be refused.
        for reference in [0.80, 0.867, 0.92] {
            let cap = FX.maxAmountIn(
                reserveIn: seededPool.usdc, reserveOut: seededPool.eurc,
                decimalsIn: 6, decimalsOut: 6, referencePrice: reference
            )
            guard cap > 0 else { continue }
            let out = try FX.amountOut(amountIn: cap, reserveIn: seededPool.usdc, reserveOut: seededPool.eurc)
            let quote = try FX.quote(
                amountIn: cap, amountOut: out,
                decimalsIn: 6, decimalsOut: 6, referencePrice: reference
            )
            XCTAssertNoThrow(try FX.assertSane(quote), "reference \(reference) offered an unquotable maximum")
        }
    }

    func testTheCeilingIsTightAndNotMerelySafe() throws {
        let cap = FX.maxAmountIn(
            reserveIn: seededPool.usdc, reserveOut: seededPool.eurc,
            decimalsIn: 6, decimalsOut: 6, referencePrice: 0.867
        )
        // A percent more is refused, so the ceiling is not leaving usable room on the
        // table. Not one unit more: across a band a few hundredths of a cent wide the
        // flooring makes single units alternate between passing and failing, and a
        // test that pinned that would be pinning noise.
        let over = cap + cap / 100
        let out = try FX.amountOut(amountIn: over, reserveIn: seededPool.usdc, reserveOut: seededPool.eurc)
        let quote = try FX.quote(
            amountIn: over, amountOut: out,
            decimalsIn: 6, decimalsOut: 6, referencePrice: 0.867
        )
        XCTAssertThrowsError(try FX.assertSane(quote))
    }

    func testADeeperPoolRaisesTheCeilingProportionally() {
        let deep = FX.maxAmountIn(
            reserveIn: seededPool.usdc * 100, reserveOut: seededPool.eurc * 100,
            decimalsIn: 6, decimalsOut: 6, referencePrice: 0.867
        )
        let shallow = FX.maxAmountIn(
            reserveIn: seededPool.usdc, reserveOut: seededPool.eurc,
            decimalsIn: 6, decimalsOut: 6, referencePrice: 0.867
        )
        // Depth is the only thing that moves the ceiling, which is the argument for a
        // faucet run rather than for loosening the guard. Not exactly a hundred times,
        // because the solved boundary is truncated to whole base units at each scale.
        XCTAssertGreaterThanOrEqual(deep, shallow * 100)
        XCTAssertLessThan(deep, shallow * 100 + shallow / 1000)
    }

    func testAPoolTooFarOffMarketOffersNoCeilingAtAll() {
        // The real Arc Swap reserves. No size works here, and claiming a maximum of
        // some tiny amount would be worse than admitting there is none.
        let cap = FX.maxAmountIn(
            reserveIn: BigUInt(300_000_000), reserveOut: BigUInt(92_110_704),
            decimalsIn: 6, decimalsOut: 6, referencePrice: 0.867
        )
        XCTAssertEqual(cap, 0)
    }

    func testAnEmptyPoolOffersNoCeiling() {
        XCTAssertEqual(
            FX.maxAmountIn(reserveIn: 0, reserveOut: 0, decimalsIn: 6, decimalsOut: 6, referencePrice: 0.867),
            0
        )
    }

    func testDecimalStringDropsTheUnitSoAFieldCanParseItBack() throws {
        let cap = USDCAmount(baseUnits: 401_486)
        XCTAssertEqual(cap.decimalString, "0.401486")
        XCTAssertEqual(cap.formatted, "0.401486 USDC")
        // The round trip the Max chip performs.
        XCTAssertEqual(try USDCAmount(decimalString: cap.decimalString).baseUnits, 401_486)
    }

    func testDeadlineIsAlwaysInTheFuture() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(FX.deadline(from: now, ttl: 300), BigUInt(1_700_000_300))
    }

    // MARK: Either direction

    func testDirectionHandsTheCurveThePoolTheRightWayRound() {
        let pool = FXReserves(usdc: 23_469_401, eurc: 19_662_648)
        XCTAssertEqual(FXDirection.usdcToEurc.reserves(pool).input, BigUInt(23_469_401))
        XCTAssertEqual(FXDirection.usdcToEurc.reserves(pool).output, BigUInt(19_662_648))
        XCTAssertEqual(FXDirection.eurcToUsdc.reserves(pool).input, BigUInt(19_662_648))
        XCTAssertEqual(FXDirection.eurcToUsdc.reserves(pool).output, BigUInt(23_469_401))
        XCTAssertEqual(FXDirection.usdcToEurc.flipped, .eurcToUsdc)
        XCTAssertEqual(FXDirection.eurcToUsdc.flipped, .usdcToEurc)
    }

    func testTheReverseReferenceIsTheInverseOfTheOneGiven() {
        XCTAssertEqual(FXDirection.usdcToEurc.reference(eurcPerUsdc: reference), reference)
        XCTAssertEqual(FXDirection.eurcToUsdc.reference(eurcPerUsdc: reference), 1 / reference, accuracy: 1e-12)
        XCTAssertEqual(FXDirection.eurcToUsdc.reference(eurcPerUsdc: 0), 0, "no reference is not an infinite one")
    }

    /// The pool as it stood on 2026-09-11, when someone holding 20 EURC found Convert
    /// only went one way. Selling euros into it is fair up to about one euro and
    /// ruinous at twenty, and the ceiling has to say which.
    func testSellingEurosIsCappedAtWhatThePoolFillsFairly() throws {
        let pool = FXDirection.eurcToUsdc.reserves(FXReserves(usdc: 23_469_401, eurc: 19_662_648))
        let fair = FXDirection.eurcToUsdc.reference(eurcPerUsdc: reference)
        let cap = FX.maxAmountIn(
            reserveIn: pool.input, reserveOut: pool.output,
            decimalsIn: 6, decimalsOut: 6, referencePrice: fair
        )
        XCTAssertGreaterThan(cap, BigUInt(1_000_000))
        XCTAssertLessThan(cap, BigUInt(1_100_000))

        let atCap = try FX.quote(
            amountIn: cap,
            amountOut: try FX.amountOut(amountIn: cap, reserveIn: pool.input, reserveOut: pool.output),
            decimalsIn: 6, decimalsOut: 6, referencePrice: fair
        )
        XCTAssertNoThrow(try FX.assertSane(atCap))

        let everything = BigUInt(20_337_352)
        let ruin = try FX.quote(
            amountIn: everything,
            amountOut: try FX.amountOut(amountIn: everything, reserveIn: pool.input, reserveOut: pool.output),
            decimalsIn: 6, decimalsOut: 6, referencePrice: fair
        )
        XCTAssertThrowsError(try FX.assertSane(ruin), "twenty euros into a pool holding twenty-three dollars loses half")
    }

    /// The same pool the other way on the same day. Buying euros was 3.7% worse than
    /// the market even for a cent, so no size was fair, and the screen told someone to
    /// try a smaller amount. A zero ceiling is an answer, not a missing one.
    func testBuyingEurosWasOffMarketAtEverySize() {
        let reserves = FXReserves(usdc: 23_469_401, eurc: 19_662_648)
        let buying = FXDirection.usdcToEurc.reserves(reserves)
        let selling = FXDirection.eurcToUsdc.reserves(reserves)
        XCTAssertEqual(FX.maxAmountIn(
            reserveIn: buying.input, reserveOut: buying.output, decimalsIn: 6, decimalsOut: 6,
            referencePrice: FXDirection.usdcToEurc.reference(eurcPerUsdc: reference)
        ), 0)
        XCTAssertGreaterThan(FX.maxAmountIn(
            reserveIn: selling.input, reserveOut: selling.output, decimalsIn: 6, decimalsOut: 6,
            referencePrice: FXDirection.eurcToUsdc.reference(eurcPerUsdc: reference)
        ), 0)
    }
}
