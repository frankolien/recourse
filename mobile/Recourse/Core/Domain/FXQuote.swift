import Foundation
@preconcurrency import BigInt

/// Converting one stablecoin into another, and knowing when not to.
///
/// Mirrors engine/src/fx.ts. The numbers here are asserted against the same inputs
/// the TypeScript suite pins, because a wallet that quoted differently from the
/// engine would show a user one figure and hand them another.
struct FXQuote: Equatable, Sendable {
    let amountIn: BigUInt
    let amountOut: BigUInt
    /// amountOut after slippage tolerance. This is the floor sent on chain.
    let minAmountOut: BigUInt
    /// Output per whole input unit. Display only, never used to size a trade.
    let price: Double
    /// How far the venue sits from an independent reference. Positive is worse.
    let deviationBps: Int?
}

enum FXQuoteError: Error, Equatable, Sendable {
    case zeroAmount
    case noLiquidity
    case offMarket(deviationBps: Int)
    case badSlippage
}

enum FX {
    /// Default tolerance between quoting and filling.
    static let defaultSlippageBps = 50

    /// How far a quote may sit from the reference before it is refused.
    ///
    /// Not a preference. The live Arc Swap pool quotes 100 USDC at 27 EURC where the
    /// real rate implies 87, so a wallet without this guard would take most of
    /// someone's money while showing them a number that looked fine. Thin and
    /// mispriced pools are the normal case on a young chain.
    static let maxDeviationBps = 200

    /// The UniswapV2 curve: 0.3% fee, integer division, floored. Floored because
    /// that is what the Solidity library does, and rounding up would quote more
    /// than the pool can actually pay.
    static func amountOut(amountIn: BigUInt, reserveIn: BigUInt, reserveOut: BigUInt) throws -> BigUInt {
        guard amountIn > 0 else { throw FXQuoteError.zeroAmount }
        guard reserveIn > 0, reserveOut > 0 else { throw FXQuoteError.noLiquidity }
        let amountInWithFee = amountIn * 997
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee)
    }

    static func applySlippage(_ amountOut: BigUInt, slippageBps: Int) throws -> BigUInt {
        guard (0...10_000).contains(slippageBps) else { throw FXQuoteError.badSlippage }
        return amountOut * BigUInt(10_000 - slippageBps) / 10_000
    }

    /// Signed: positive when the venue offers less than the reference.
    static func deviationBps(price: Double, reference: Double) -> Int {
        guard reference > 0 else { return 0 }
        return Int((((reference - price) / reference) * 10_000).rounded())
    }

    /// Builds the quote a user is shown. Decimals are equal for USDC and EURC on
    /// Arc, but taken as parameters so a token with different precision cannot
    /// silently produce a wrong display price.
    static func quote(
        amountIn: BigUInt,
        amountOut: BigUInt,
        decimalsIn: Int,
        decimalsOut: Int,
        slippageBps: Int = defaultSlippageBps,
        referencePrice: Double? = nil
    ) throws -> FXQuote {
        guard amountIn > 0 else { throw FXQuoteError.zeroAmount }
        guard amountOut > 0 else { throw FXQuoteError.noLiquidity }

        let humanIn = Double(amountIn) / pow(10, Double(decimalsIn))
        let humanOut = Double(amountOut) / pow(10, Double(decimalsOut))
        let price = humanIn > 0 ? humanOut / humanIn : 0

        return FXQuote(
            amountIn: amountIn,
            amountOut: amountOut,
            minAmountOut: try applySlippage(amountOut, slippageBps: slippageBps),
            price: price,
            deviationBps: referencePrice.map { deviationBps(price: price, reference: $0) }
        )
    }

    /// The check that runs before anything is signed. Kept separate from quoting so
    /// a venue cannot mark its own homework, and so a refusal has a reason.
    static func assertSane(_ quote: FXQuote, maxDeviationBps: Int = FX.maxDeviationBps) throws {
        guard quote.amountOut > 0, quote.minAmountOut > 0 else { throw FXQuoteError.noLiquidity }
        if let deviation = quote.deviationBps, deviation > maxDeviationBps {
            throw FXQuoteError.offMarket(deviationBps: deviation)
        }
    }

    /// A swap must never be signed without one: an open ended order can sit unmined
    /// and execute later at a price nobody agreed to.
    static func deadline(from now: Date = Date(), ttl: TimeInterval = 300) -> BigUInt {
        BigUInt(UInt64(now.timeIntervalSince1970 + ttl))
    }
}
