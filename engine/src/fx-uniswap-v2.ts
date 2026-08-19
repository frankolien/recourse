// A Uniswap V2 venue behind the FXVenue interface.
//
// Quotes come from getAmountsOut on the router rather than from reserves, so the
// number quoted is the number the swap will produce: same curve, same fee, same
// rounding. Deriving a price from reserves and then swapping is how quotes and
// fills drift apart.

import { DEFAULT_SLIPPAGE_BPS, FXError, applySlippage, deviationBps } from "./fx";
import type { FXVenue, Quote, QuoteRequest } from "./fx";

export interface RouterReader {
  /** UniswapV2Router02.getAmountsOut. Returns one amount per hop. */
  getAmountsOut(amountIn: bigint, path: readonly `0x${string}`[]): Promise<readonly bigint[]>;
}

export interface UniswapV2VenueOptions {
  name?: string;
  router: RouterReader;
  /** Decimals per token, needed only to render a human price. */
  decimals: Record<string, number>;
  /** Hops to try in order. Direct pair first. */
  intermediates?: readonly `0x${string}`[];
}

export class UniswapV2Venue implements FXVenue {
  readonly name: string;
  private readonly router: RouterReader;
  private readonly decimals: Record<string, number>;
  private readonly intermediates: readonly `0x${string}`[];

  constructor(options: UniswapV2VenueOptions) {
    this.name = options.name ?? "uniswap-v2";
    this.router = options.router;
    this.decimals = Object.fromEntries(
      Object.entries(options.decimals).map(([k, v]) => [k.toLowerCase(), v]),
    );
    this.intermediates = options.intermediates ?? [];
  }

  async quote(request: QuoteRequest): Promise<Quote> {
    const { tokenIn, tokenOut, amountIn } = request;
    if (amountIn <= 0n) throw new FXError("amountIn must be positive.", "bad_amount");
    if (tokenIn.toLowerCase() === tokenOut.toLowerCase()) {
      throw new FXError("tokenIn and tokenOut are the same token.", "same_token");
    }

    const paths: `0x${string}`[][] = [[tokenIn, tokenOut]];
    for (const mid of this.intermediates) {
      if (mid.toLowerCase() === tokenIn.toLowerCase() || mid.toLowerCase() === tokenOut.toLowerCase()) continue;
      paths.push([tokenIn, mid, tokenOut]);
    }

    let best: { out: bigint; path: `0x${string}`[] } | null = null;
    const failures: string[] = [];
    for (const path of paths) {
      try {
        const amounts = await this.router.getAmountsOut(amountIn, path);
        const out = amounts[amounts.length - 1];
        // A pair that does not exist reverts, but an empty one can return zero.
        if (out === undefined || out <= 0n) continue;
        if (!best || out > best.out) best = { out, path };
      } catch (error) {
        failures.push((error as Error).message);
      }
    }

    if (!best) {
      throw new FXError(
        `${this.name} has no route from ${tokenIn} to ${tokenOut}.`,
        failures.length ? "no_route" : "no_liquidity",
      );
    }

    const slippageBps = request.slippageBps ?? DEFAULT_SLIPPAGE_BPS;
    const price = this.humanPrice(amountIn, best.out, tokenIn, tokenOut);

    return {
      amountIn,
      amountOut: best.out,
      minAmountOut: applySlippage(best.out, slippageBps),
      price,
      deviationBps: request.referencePrice ? deviationBps(price, request.referencePrice) : null,
      route: best.path,
      venue: this.name,
    };
  }

  /** Display only. Sizing is done in atomic units so nothing rounds through a float. */
  private humanPrice(amountIn: bigint, amountOut: bigint, tokenIn: string, tokenOut: string): number {
    const dIn = this.decimals[tokenIn.toLowerCase()] ?? 18;
    const dOut = this.decimals[tokenOut.toLowerCase()] ?? 18;
    return (Number(amountOut) / 10 ** dOut) / (Number(amountIn) / 10 ** dIn);
  }
}

/** Mirrors UniswapV2Library.getAmountOut, for tests and for local sizing. */
export function getAmountOut(amountIn: bigint, reserveIn: bigint, reserveOut: bigint): bigint {
  if (amountIn <= 0n) throw new FXError("amountIn must be positive.", "bad_amount");
  if (reserveIn <= 0n || reserveOut <= 0n) throw new FXError("pair has no reserves.", "no_liquidity");
  const amountInWithFee = amountIn * 997n;
  return (amountInWithFee * reserveOut) / (reserveIn * 1000n + amountInWithFee);
}

/**
 * A swap must not be signed without a deadline: without one it can sit in the
 * mempool and execute at a price nobody agreed to.
 */
export function swapDeadline(nowSeconds: number, ttlSeconds = 300): bigint {
  if (!Number.isFinite(nowSeconds)) throw new FXError("nowSeconds must be a number.", "bad_deadline");
  return BigInt(Math.floor(nowSeconds) + ttlSeconds);
}
