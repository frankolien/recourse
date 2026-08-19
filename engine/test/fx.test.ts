import { describe, it, expect } from "vitest";
import { FXError, applySlippage, assertQuoteSane, deviationBps, MAX_DEVIATION_BPS } from "../src/fx";
import type { Quote } from "../src/fx";
import { UniswapV2Venue, getAmountOut, swapDeadline } from "../src/fx-uniswap-v2";
import type { RouterReader } from "../src/fx-uniswap-v2";

const USDC = "0x3600000000000000000000000000000000000000" as const;
const EURC = "0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a" as const;
const WBTC = "0x00000000000000000000000000000000000000bc" as const;

const DECIMALS = { [USDC]: 6, [EURC]: 6, [WBTC]: 8 };

/** A pool priced however the test wants, using the real V2 curve. */
function pool(reserveIn: bigint, reserveOut: bigint): RouterReader {
  return {
    getAmountsOut: async (amountIn, path) => {
      if (path.length !== 2) throw new Error("no such pair");
      return [amountIn, getAmountOut(amountIn, reserveIn, reserveOut)];
    },
  };
}

const venue = (router: RouterReader, intermediates: readonly `0x${string}`[] = []) =>
  new UniswapV2Venue({ router, decimals: DECIMALS, intermediates });

describe("uniswap v2 quoting", () => {
  // A pool at the real EUR/USD rate: 100k USDC against 86.7k EURC.
  const fair = pool(100_000_000_000n, 86_700_000_000n);

  it("quotes from the router rather than from reserves", async () => {
    const q = await venue(fair).quote({ tokenIn: USDC, tokenOut: EURC, amountIn: 100_000_000n });
    // 100 USDC into a deep, correctly priced pool lands near the reference.
    expect(q.price).toBeGreaterThan(0.85);
    expect(q.price).toBeLessThan(0.87);
    expect(q.route).toEqual([USDC, EURC]);
    expect(q.venue).toBe("uniswap-v2");
  });

  it("floors the output by the slippage tolerance", async () => {
    const q = await venue(fair).quote({ tokenIn: USDC, tokenOut: EURC, amountIn: 100_000_000n, slippageBps: 100 });
    expect(q.minAmountOut).toBe((q.amountOut * 9_900n) / 10_000n);
    expect(q.minAmountOut).toBeLessThan(q.amountOut);
  });

  it("prices size, so a large order quotes worse than a small one", async () => {
    const small = await venue(fair).quote({ tokenIn: USDC, tokenOut: EURC, amountIn: 10_000_000n });
    const large = await venue(fair).quote({ tokenIn: USDC, tokenOut: EURC, amountIn: 50_000_000_000n });
    expect(large.price).toBeLessThan(small.price);
  });

  it("takes the better of a direct pair and a hop", async () => {
    const router: RouterReader = {
      getAmountsOut: async (amountIn, path) => {
        if (path.length === 2) return [amountIn, amountIn / 2n]; // poor direct pair
        return [amountIn, amountIn, (amountIn * 9n) / 10n]; // better through WBTC
      },
    };
    const q = await venue(router, [WBTC]).quote({ tokenIn: USDC, tokenOut: EURC, amountIn: 1_000_000n });
    expect(q.route).toEqual([USDC, WBTC, EURC]);
    expect(q.amountOut).toBe(900_000n);
  });

  it("reports no route when every path reverts", async () => {
    const dead: RouterReader = { getAmountsOut: async () => { throw new Error("no pair"); } };
    await expect(venue(dead).quote({ tokenIn: USDC, tokenOut: EURC, amountIn: 1_000_000n }))
      .rejects.toThrow(FXError);
  });

  it("rejects nonsense before touching the chain", async () => {
    const v = venue(fair);
    await expect(v.quote({ tokenIn: USDC, tokenOut: USDC, amountIn: 1n })).rejects.toThrow(FXError);
    await expect(v.quote({ tokenIn: USDC, tokenOut: EURC, amountIn: 0n })).rejects.toThrow(FXError);
  });
});

describe("the guard against a mispriced venue", () => {
  // The real Arc Swap pool as measured on 2026-08-13. This is not hypothetical:
  // quoting it without a check is how a wallet takes most of someone's money.
  const arcSwap = pool(236_062_365n, 92_110_704n);
  const REFERENCE = 1 / 1.1534; // EUR/USD 1.1534, so ~0.867 EURC per USDC

  it("measures how far off market the live Arc pool is", async () => {
    const q = await venue(arcSwap).quote({
      tokenIn: USDC, tokenOut: EURC, amountIn: 100_000_000n, referencePrice: REFERENCE,
    });
    // 100 USDC quotes ~27 EURC where the reference implies ~87.
    expect(q.amountOut).toBeLessThan(30_000_000n);
    expect(q.deviationBps).toBeGreaterThan(6_000);
  });

  it("refuses to convert through it", async () => {
    const q = await venue(arcSwap).quote({
      tokenIn: USDC, tokenOut: EURC, amountIn: 100_000_000n, referencePrice: REFERENCE,
    });
    expect(() => assertQuoteSane(q)).toThrow(/worse than the reference/);
  });

  it("passes a correctly priced pool at the same size", async () => {
    const q = await venue(pool(100_000_000_000n, 86_700_000_000n)).quote({
      tokenIn: USDC, tokenOut: EURC, amountIn: 100_000_000n, referencePrice: REFERENCE,
    });
    expect(q.deviationBps).toBeLessThan(MAX_DEVIATION_BPS);
    expect(() => assertQuoteSane(q)).not.toThrow();
  });

  it("does not block a venue that quotes better than the reference", () => {
    const generous: Quote = {
      amountIn: 1n, amountOut: 2n, minAmountOut: 1n, price: 1.2,
      deviationBps: deviationBps(1.2, 1.0), route: [USDC, EURC], venue: "x",
    };
    expect(generous.deviationBps).toBeLessThan(0);
    expect(() => assertQuoteSane(generous)).not.toThrow();
  });

  it("refuses a quote that slippage has consumed entirely", () => {
    const dust: Quote = {
      amountIn: 1n, amountOut: 1n, minAmountOut: 0n, price: 1, deviationBps: 0,
      route: [USDC, EURC], venue: "x",
    };
    expect(() => assertQuoteSane(dust)).toThrow(/slippage/);
  });
});

describe("arithmetic", () => {
  it("matches the UniswapV2 fee curve", () => {
    // (997 * 1e6 * 2e9) / (1e9 * 1000 + 997 * 1e6) = 1992013.96..., floored.
    // The floor is the point: integer division is what the Solidity library does,
    // and rounding up here would quote more than the pool can pay.
    expect(getAmountOut(1_000_000n, 1_000_000_000n, 2_000_000_000n)).toBe(1_992_013n);
  });

  it("rejects an empty pair rather than dividing by zero", () => {
    expect(() => getAmountOut(1n, 0n, 1n)).toThrow(FXError);
    expect(() => getAmountOut(1n, 1n, 0n)).toThrow(FXError);
  });

  it("applies slippage in integer basis points", () => {
    expect(applySlippage(10_000n, 50)).toBe(9_950n);
    expect(applySlippage(10_000n, 0)).toBe(10_000n);
    expect(() => applySlippage(1n, 10_001)).toThrow(FXError);
    expect(() => applySlippage(1n, 1.5)).toThrow(FXError);
  });

  it("gives a swap a deadline, because one without can execute at any price later", () => {
    expect(swapDeadline(1_700_000_000, 300)).toBe(1_700_000_300n);
    expect(() => swapDeadline(Number.NaN)).toThrow(FXError);
  });
});
