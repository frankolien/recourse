// Converting one stablecoin into another, behind an interface.
//
// The interface exists because of what is on Arc today rather than as speculative
// abstraction. Measured 2026-08-13: the only DEX holds under $600 across 39 pairs,
// its one stablecoin pool is mispriced 2.2x, and StableFX settles bilateral RFQs
// behind an on chain relayer allowlist. Neither can be quoted honestly. So the app
// talks to a venue, testnet points at a pool we seed ourselves, and mainnet points
// at whichever real venue exists on the day without the caller changing.

export interface Quote {
  /** Atomic units of the input token. */
  amountIn: bigint;
  /** Atomic units the venue expects to return, before slippage. */
  amountOut: bigint;
  /** amountOut after the caller's slippage tolerance; the floor to enforce. */
  minAmountOut: bigint;
  /** Output per whole input unit, for display only. Never used to size a trade. */
  price: number;
  /** How far this quote sits from an independent reference, in basis points. */
  deviationBps: number | null;
  route: readonly `0x${string}`[];
  venue: string;
}

export interface QuoteRequest {
  tokenIn: `0x${string}`;
  tokenOut: `0x${string}`;
  amountIn: bigint;
  /** Defaults to 50 bps. */
  slippageBps?: number;
  /** Reference rate for the sanity check, output per input. */
  referencePrice?: number;
}

export interface FXVenue {
  readonly name: string;
  quote(request: QuoteRequest): Promise<Quote>;
}

export class FXError extends Error {
  constructor(message: string, readonly reason: string) {
    super(message);
    this.name = "FXError";
  }
}

export const DEFAULT_SLIPPAGE_BPS = 50;

/**
 * How far a quote may sit from the reference before it is refused outright.
 *
 * A wallet that quietly executed the Arc Swap price would have taken 68% of a
 * user's money on a $100 convert and shown them a number that looked fine. Thin
 * and mispriced pools are the normal case on a young chain, so the guard is a
 * default rather than an option.
 */
export const MAX_DEVIATION_BPS = 200;

export function applySlippage(amountOut: bigint, slippageBps: number): bigint {
  if (!Number.isInteger(slippageBps) || slippageBps < 0 || slippageBps > 10_000) {
    throw new FXError("slippageBps must be an integer in [0, 10000].", "bad_slippage");
  }
  return (amountOut * BigInt(10_000 - slippageBps)) / 10_000n;
}

/** Signed: positive when the venue offers less than the reference. */
export function deviationBps(price: number, reference: number): number {
  if (!(reference > 0)) throw new FXError("reference price must be positive.", "bad_reference");
  return Math.round(((reference - price) / reference) * 10_000);
}

/**
 * The check a caller runs before signing. Separate from quoting so a venue cannot
 * mark its own homework, and so the reason a convert was refused is inspectable.
 */
export function assertQuoteSane(quote: Quote, maxDeviationBps = MAX_DEVIATION_BPS): void {
  if (quote.amountOut <= 0n) {
    throw new FXError(`${quote.venue} returned nothing for this size.`, "no_liquidity");
  }
  if (quote.minAmountOut <= 0n) {
    throw new FXError(`${quote.venue} quote is entirely consumed by slippage.`, "no_liquidity");
  }
  if (quote.deviationBps !== null && quote.deviationBps > maxDeviationBps) {
    throw new FXError(
      `${quote.venue} is ${(quote.deviationBps / 100).toFixed(1)}% worse than the reference rate.`,
      "off_market",
    );
  }
}
