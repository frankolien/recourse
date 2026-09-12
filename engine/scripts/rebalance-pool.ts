// Puts the testnet FX pool back on price, then makes it deeper.
//
//   ops/rebalance-pool.sh --anvil    dry run on a throwaway node
//   ops/rebalance-pool.sh --live     Arc testnet
//
// Two legs, and the order is the point. Every trade against a pool moves its price,
// nothing arbitrages a testnet, and the wallet refuses a quote more than 200 bps off
// the reference. So the pool ends up in a state where Convert declines sizes that
// look reasonable to the person holding the phone. Leg one sells whichever side
// pushes the price back to the reference; leg two adds what is left as liquidity.
//
// Correcting before deepening is the cheaper order: the trade that moves a shallow
// pool one percent is smaller than the one that moves a deep pool the same percent,
// and EURC is the scarce input here because Circle's faucet caps at 20 per request.

import { readFileSync } from "node:fs";
import { createPublicClient, createWalletClient, defineChain, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { Address, Hex } from "viem";
import { UniswapV2Venue, swapDeadline } from "../src/fx-uniswap-v2";
import { assertQuoteSane, deviationBps } from "../src/fx";

const env = (name: string, fallback?: string): string => {
  const value = process.env[name] ?? fallback;
  if (value === undefined) throw new Error(`${name} is required`);
  return value;
};

const RPC = env("SEED_RPC");
const CHAIN_ID = Number(env("SEED_CHAIN_ID"));
const KEY = env("SEED_KEY") as Hex;
const LIVE = CHAIN_ID !== 31337;
// EURC per USDC, and it must match ConvertView's referencePrice or the app will
// refuse a pool this script just declared healthy.
const REFERENCE = Number(env("SEED_REFERENCE", "0.867"));
// Arc charges gas in USDC, so spending the balance to the last unit leaves an
// account that cannot pay for the next transaction.
const GAS_BUFFER = BigInt(env("SEED_GAS_BUFFER", "1000000"));
// Below this the correcting trade costs more in fees than the drift is worth.
const SKIP_BPS = Number(env("SEED_SKIP_BPS", "10"));

const chain = defineChain({
  id: CHAIN_ID,
  name: LIVE ? "Arc" : "Anvil",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [RPC] } },
});

const account = privateKeyToAccount(KEY);
const publicClient = createPublicClient({ chain, transport: http(RPC) });
const walletClient = createWalletClient({ account, chain, transport: http(RPC) });

const erc20 = parseAbi([
  "function approve(address spender, uint256 amount) returns (bool)",
  "function balanceOf(address a) view returns (uint256)",
  "function mint(address to, uint256 amount)",
  "function isBlacklisted(address a) view returns (bool)",
]);
const routerAbi = parseAbi([
  "function createPair(address tokenA, address tokenB) returns (address)",
  "function getPair(address tokenA, address tokenB) view returns (address)",
  "function addLiquidity((address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) p) returns (uint256, uint256, uint256)",
  "function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] path, address to, uint256 deadline) returns (uint256[])",
  "function getAmountsOut(uint256 amountIn, address[] path) view returns (uint256[])",
]);
const pairAbi = parseAbi([
  "function token0() view returns (address)",
  "function getReserves() view returns (uint112, uint112)",
]);

const artifact = (name: string) =>
  JSON.parse(readFileSync(new URL(`../../contracts/out/${name}.sol/${name}.json`, import.meta.url), "utf8"));

async function confirm(hash: Hex, label: string) {
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`${label} reverted`);
  return receipt;
}

async function deploy(name: string, args: unknown[]): Promise<Address> {
  const a = artifact(name);
  const hash = await walletClient.deployContract({ abi: a.abi, bytecode: a.bytecode.object as Hex, args });
  const receipt = await confirm(hash, `deploy ${name}`);
  return receipt.contractAddress!;
}

const units = (v: bigint) => Number(v) / 1e6;

/**
 * How much of the sold token to push in so that afterwards the pool holds `target`
 * of it per unit of the other side.
 *
 * Solved rather than searched. Substituting the constant product output into
 * (rSell + a) / (rOther - out) = target reduces to 997a^2 + 1997*rSell*a +
 * 1000*rSell*(rSell - target*rOther) = 0, and only the positive root sits on the
 * curve. Whole token units keep the squared terms inside a double's precision.
 */
function inputToReachRatio(rSell: number, rOther: number, target: number): number {
  const b = 1997 * rSell;
  const c = 1000 * rSell * (rSell - target * rOther);
  const discriminant = b * b - 4 * 997 * c;
  if (discriminant <= 0) return 0;
  const root = (-b + Math.sqrt(discriminant)) / (2 * 997);
  return root > 0 ? root : 0;
}

async function reserves(pair: Address, usdc: Address): Promise<{ usdc: bigint; eurc: bigint }> {
  const [token0, pool] = await Promise.all([
    publicClient.readContract({ address: pair, abi: pairAbi, functionName: "token0" }),
    publicClient.readContract({ address: pair, abi: pairAbi, functionName: "getReserves" }),
  ]);
  const [r0, r1] = pool as readonly [bigint, bigint];
  const zeroIsUsdc = (token0 as Address).toLowerCase() === usdc.toLowerCase();
  return zeroIsUsdc ? { usdc: r0, eurc: r1 } : { usdc: r1, eurc: r0 };
}

console.log(`rebalancing as ${account.address} on chain ${CHAIN_ID}`);

let usdc = process.env.SEED_USDC_TOKEN as Address | undefined;
let eurc = process.env.SEED_EURC_TOKEN as Address | undefined;
let router = process.env.SEED_ROUTER as Address | undefined;
let pair = process.env.SEED_PAIR as Address | undefined;

if (LIVE) {
  if (!usdc || !eurc || !router || !pair) {
    throw new Error("SEED_USDC_TOKEN, SEED_EURC_TOKEN, SEED_ROUTER and SEED_PAIR are required against a live chain");
  }
  // Arc USDC and EURC are Circle FiatTokens and carry a blacklist. A blocked
  // account reverts inside whatever call touches it, which reads as a contract bug.
  for (const [name, token] of [["USDC", usdc], ["EURC", eurc]] as const) {
    const blocked = await publicClient.readContract({
      address: token, abi: erc20, functionName: "isBlacklisted", args: [account.address],
    });
    if (blocked) throw new Error(`${account.address} is blacklisted on ${name}`);
  }
} else {
  // The dry run builds its own pool and puts it deliberately off price, so the
  // correction runs against the same shape of problem the live pool is in.
  usdc = await deploy("TestUSDC", []);
  eurc = await deploy("TestUSDC", []);
  for (const token of [usdc, eurc]) {
    await confirm(
      await walletClient.writeContract({
        address: token, abi: erc20, functionName: "mint", args: [account.address, 10n ** 12n],
      }),
      "mint",
    );
  }
  router = await deploy("MiniRouter", []);
  await confirm(
    await walletClient.writeContract({
      address: router, abi: routerAbi, functionName: "createPair", args: [usdc, eurc],
    }),
    "createPair",
  );
  pair = (await publicClient.readContract({
    address: router, abi: routerAbi, functionName: "getPair", args: [usdc, eurc],
  })) as Address;
  const skewedUsdc = 23_469_401n;
  const skewedEurc = 19_662_648n;
  for (const [token, amount] of [[usdc, skewedUsdc], [eurc, skewedEurc]] as const) {
    await confirm(
      await walletClient.writeContract({
        address: token, abi: erc20, functionName: "approve", args: [router, amount],
      }),
      "approve",
    );
  }
  await confirm(
    await walletClient.writeContract({
      address: router, abi: routerAbi, functionName: "addLiquidity",
      args: [{
        tokenA: usdc, tokenB: eurc,
        amountADesired: skewedUsdc, amountBDesired: skewedEurc,
        amountAMin: 0n, amountBMin: 0n,
        to: account.address,
        deadline: swapDeadline(Math.floor(Date.now() / 1000)),
      }],
    }),
    "addLiquidity",
  );
  console.log(`  dry run pool seeded off price at ${(Number(skewedEurc) / Number(skewedUsdc)).toFixed(4)}`);
}

console.log(`  router ${router}`);
console.log(`  pair   ${pair}`);

const before = await reserves(pair!, usdc!);
const poolPrice = Number(before.eurc) / Number(before.usdc);
const drift = deviationBps(poolPrice, REFERENCE);
console.log(
  `\n  pool holds ${units(before.usdc)} USDC against ${units(before.eurc)} EURC` +
  `\n  price ${poolPrice.toFixed(6)} EURC per USDC, reference ${REFERENCE}, drift ${drift} bps`,
);

// Leg one: sell whichever side moves the price back toward the reference. Selling
// EURC raises EURC per USDC because it takes USDC out of the pool, so an
// undervalued pool is corrected by selling euros into it, and the reverse.
if (Math.abs(drift) <= SKIP_BPS) {
  console.log(`  within ${SKIP_BPS} bps already, no correcting trade`);
} else {
  const sellEurc = poolPrice < REFERENCE;
  const tokenIn = sellEurc ? eurc! : usdc!;
  const tokenOut = sellEurc ? usdc! : eurc!;
  const rSell = units(sellEurc ? before.eurc : before.usdc);
  const rOther = units(sellEurc ? before.usdc : before.eurc);
  const target = sellEurc ? REFERENCE : 1 / REFERENCE;

  const needed = inputToReachRatio(rSell, rOther, target);
  const amountIn = BigInt(Math.floor(needed * 1e6));
  if (amountIn <= 0n) throw new Error("the correcting trade solved to nothing, which means the drift was misread");

  const held = (await publicClient.readContract({
    address: tokenIn, abi: erc20, functionName: "balanceOf", args: [account.address],
  })) as bigint;
  const label = sellEurc ? "EURC" : "USDC";
  if (held < amountIn) {
    throw new Error(
      `correcting this pool needs ${units(amountIn)} ${label} and ${account.address} holds ${units(held)}. ` +
      `Faucet ${label} to that address, then run this again.`,
    );
  }

  console.log(`  selling ${units(amountIn)} ${label} to bring the pool back to ${REFERENCE}`);
  await confirm(
    await walletClient.writeContract({
      address: tokenIn, abi: erc20, functionName: "approve", args: [router!, amountIn],
    }),
    "approve",
  );
  await confirm(
    await walletClient.writeContract({
      address: router!, abi: routerAbi, functionName: "swapExactTokensForTokens",
      // Nothing else trades this pool, and the quote was computed from reserves read
      // one block ago, so the floor exists to catch a reordering rather than a market.
      args: [amountIn, 0n, [tokenIn, tokenOut], account.address, swapDeadline(Math.floor(Date.now() / 1000))],
      // Arc's eth_estimateGas is unreliable, so the limit is set explicitly there.
      gas: LIVE ? 3_000_000n : undefined,
    }),
    "correcting swap",
  );

  const corrected = await reserves(pair!, usdc!);
  const price = Number(corrected.eurc) / Number(corrected.usdc);
  console.log(`  price is now ${price.toFixed(6)}, drift ${deviationBps(price, REFERENCE)} bps`);
}

// Leg two: add whatever is left. The router trims the deposit to the pool's ratio,
// which is the ratio leg one just set, so this deepens the pool without moving it.
const mid = await reserves(pair!, usdc!);
const [heldUsdc, heldEurc] = (await Promise.all([
  publicClient.readContract({ address: usdc!, abi: erc20, functionName: "balanceOf", args: [account.address] }),
  publicClient.readContract({ address: eurc!, abi: erc20, functionName: "balanceOf", args: [account.address] }),
])) as [bigint, bigint];

const spendUsdc = heldUsdc > GAS_BUFFER ? heldUsdc - GAS_BUFFER : 0n;
console.log(`\n  holding ${units(heldUsdc)} USDC and ${units(heldEurc)} EURC, keeping ${units(GAS_BUFFER)} USDC for gas`);

if (spendUsdc === 0n || heldEurc === 0n) {
  console.log("  nothing to add. Faucet both tokens to this address to deepen the pool.");
} else {
  // Whichever side runs out first decides the deposit, because the router trims the
  // other to match. Stating the floor explicitly means a reordered block reverts
  // rather than quietly depositing at a price nobody chose.
  const optimalEurc = (spendUsdc * mid.eurc) / mid.usdc;
  const limitedByUsdc = optimalEurc <= heldEurc;
  const addUsdc = limitedByUsdc ? spendUsdc : (heldEurc * mid.usdc) / mid.eurc;
  const addEurc = limitedByUsdc ? optimalEurc : heldEurc;

  for (const [token, amount] of [[usdc!, addUsdc], [eurc!, addEurc]] as const) {
    await confirm(
      await walletClient.writeContract({
        address: token, abi: erc20, functionName: "approve", args: [router!, amount],
      }),
      "approve",
    );
  }
  await confirm(
    await walletClient.writeContract({
      address: router!, abi: routerAbi, functionName: "addLiquidity",
      args: [{
        tokenA: usdc!, tokenB: eurc!,
        amountADesired: addUsdc, amountBDesired: addEurc,
        amountAMin: (addUsdc * 99n) / 100n, amountBMin: (addEurc * 99n) / 100n,
        to: account.address,
        deadline: swapDeadline(Math.floor(Date.now() / 1000)),
      }],
      gas: LIVE ? 6_000_000n : undefined,
    }),
    "addLiquidity",
  );
  console.log(`  added ${units(addUsdc)} USDC and ${units(addEurc)} EURC`);
}

// Quote it back through the venue the wallet uses, held to the wallet's guard, in
// both directions. A pool that is healthy one way and refused the other is exactly
// the state Convert was in before this script existed.
const after = await reserves(pair!, usdc!);
const finalPrice = Number(after.eurc) / Number(after.usdc);
console.log(
  `\n  pool now holds ${units(after.usdc)} USDC against ${units(after.eurc)} EURC` +
  `\n  price ${finalPrice.toFixed(6)}, drift ${deviationBps(finalPrice, REFERENCE)} bps`,
);

const venue = new UniswapV2Venue({
  name: "recourse-pool",
  decimals: { [usdc!]: 6, [eurc!]: 6 },
  router: {
    getAmountsOut: (amountIn, path) =>
      publicClient.readContract({
        address: router!, abi: routerAbi, functionName: "getAmountsOut", args: [amountIn, path as Address[]],
      }) as Promise<readonly bigint[]>,
  },
});

const ladder = [100_000n, 250_000n, 500_000n, 1_000_000n, 2_000_000n, 5_000_000n];
const largest: Record<string, bigint> = {};
for (const [from, to, reference, name] of [
  [usdc!, eurc!, REFERENCE, "USDC into EURC"],
  [eurc!, usdc!, 1 / REFERENCE, "EURC into USDC"],
] as const) {
  console.log(`\n  ${name}\n  size      out        deviation   guard`);
  largest[name] = 0n;
  for (const size of ladder) {
    const q = await venue.quote({ tokenIn: from, tokenOut: to, amountIn: size, referencePrice: reference });
    let verdict = "pass";
    try {
      assertQuoteSane(q);
      if (size > largest[name]) largest[name] = size;
    } catch (error) {
      verdict = `refused (${(error as Error).message.split(" is ")[1] ?? "off market"})`;
    }
    console.log(
      `  ${units(size).toFixed(2).padStart(5)}  ${units(q.amountOut).toFixed(4).padStart(9)}` +
      `  ${String(q.deviationBps).padStart(6)} bps  ${verdict}`,
    );
  }
}

for (const [name, size] of Object.entries(largest)) {
  if (size === 0n) throw new Error(`the wallet would refuse ${name} at every size on this pool`);
  console.log(`\n  the wallet will convert up to ${units(size)} ${name}`);
}

console.log(JSON.stringify({
  chainId: CHAIN_ID,
  router,
  pair,
  usdc: after.usdc.toString(),
  eurc: after.eurc.toString(),
  price: Number(finalPrice.toFixed(6)),
  referenceRate: REFERENCE,
}, null, 2));
