// Deploys the testnet FX venue and seeds it, then quotes it back through the same
// code the wallet uses and holds it to the same guard.
//
//   ops/seed-pool.sh --anvil     dry run on a throwaway node
//   ops/seed-pool.sh --live      Arc testnet
//
// Seeding sets the price: the ratio deposited into an empty pair is the rate it
// trades at until someone arbitrages it. That is exactly how the existing Arc Swap
// pool ended up 2.2x off, so the last step here re-quotes the pool and fails if the
// wallet would refuse to trade against what was just seeded.

import { readFileSync } from "node:fs";
import { createPublicClient, createWalletClient, defineChain, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { Address, Hex } from "viem";
import { UniswapV2Venue, swapDeadline } from "../src/fx-uniswap-v2";
import { assertQuoteSane } from "../src/fx";

const env = (name: string, fallback?: string): string => {
  const value = process.env[name] ?? fallback;
  if (value === undefined) throw new Error(`${name} is required`);
  return value;
};

const RPC = env("SEED_RPC");
const CHAIN_ID = Number(env("SEED_CHAIN_ID"));
const KEY = env("SEED_KEY") as Hex;
const LIVE = CHAIN_ID !== 31337;
// EURC per USDC. EUR/USD was 1.1534 on 2026-08-13.
const REFERENCE = Number(env("SEED_REFERENCE", "0.867"));
const USDC_AMOUNT = BigInt(env("SEED_USDC_AMOUNT", "23070000"));
const EURC_AMOUNT = BigInt(env("SEED_EURC_AMOUNT", "20000000"));

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
  "function getAmountsOut(uint256 amountIn, address[] path) view returns (uint256[])",
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

console.log(`seeding as ${account.address} on chain ${CHAIN_ID}`);

let usdc = process.env.SEED_USDC_TOKEN as Address | undefined;
let eurc = process.env.SEED_EURC_TOKEN as Address | undefined;

if (!usdc || !eurc) {
  if (LIVE) throw new Error("SEED_USDC_TOKEN and SEED_EURC_TOKEN are required against a live chain");
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
  console.log(`  mock tokens ${usdc} / ${eurc}`);
}

if (LIVE) {
  // Arc USDC and EURC are Circle FiatTokens and carry a blacklist. A blocked
  // account reverts inside whatever call touches it, which reads as a contract bug.
  for (const [name, token] of [["USDC", usdc], ["EURC", eurc]] as const) {
    const blocked = await publicClient.readContract({
      address: token, abi: erc20, functionName: "isBlacklisted", args: [account.address],
    });
    if (blocked) throw new Error(`${account.address} is blacklisted on ${name}`);
  }
  for (const [name, token, need] of [["USDC", usdc, USDC_AMOUNT], ["EURC", eurc, EURC_AMOUNT]] as const) {
    const held = await publicClient.readContract({
      address: token, abi: erc20, functionName: "balanceOf", args: [account.address],
    });
    if (held < need) throw new Error(`need ${need} ${name} to seed, hold ${held}`);
  }
  console.log("  preflight ok: not blacklisted, balances cover the seed");
}

const router = (process.env.SEED_ROUTER as Address | undefined) ?? (await deploy("MiniRouter", []));
console.log(`  router ${router}`);

let pair = await publicClient.readContract({
  address: router, abi: routerAbi, functionName: "getPair", args: [usdc, eurc],
});
if (pair === "0x0000000000000000000000000000000000000000") {
  // Arc's eth_estimateGas is unreliable and pair creation costs far more than a
  // default estimate, so the limit is set explicitly there.
  await confirm(
    await walletClient.writeContract({
      address: router, abi: routerAbi, functionName: "createPair", args: [usdc, eurc],
      gas: LIVE ? 5_000_000n : undefined,
    }),
    "createPair",
  );
  pair = await publicClient.readContract({
    address: router, abi: routerAbi, functionName: "getPair", args: [usdc, eurc],
  });
}
console.log(`  pair ${pair}`);

for (const [token, amount] of [[usdc, USDC_AMOUNT], [eurc, EURC_AMOUNT]] as const) {
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
      amountADesired: USDC_AMOUNT, amountBDesired: EURC_AMOUNT,
      amountAMin: 0n, amountBMin: 0n,
      to: account.address,
      deadline: swapDeadline(Math.floor(Date.now() / 1000)),
    }],
    gas: LIVE ? 6_000_000n : undefined,
  }),
  "addLiquidity",
);
console.log(`  seeded ${Number(USDC_AMOUNT) / 1e6} USDC against ${Number(EURC_AMOUNT) / 1e6} EURC`);

// Quote it back through the venue the wallet uses, held to the wallet's guard.
// Seeding a pool the app would then refuse to trade is a silent failure otherwise.
const venue = new UniswapV2Venue({
  name: "recourse-pool",
  decimals: { [usdc]: 6, [eurc]: 6 },
  router: {
    getAmountsOut: (amountIn, path) =>
      publicClient.readContract({
        address: router, abi: routerAbi, functionName: "getAmountsOut", args: [amountIn, path as Address[]],
      }) as Promise<readonly bigint[]>,
  },
});

console.log("\n  size      out        deviation   guard");
let largestSane = 0n;
for (const size of [100_000n, 250_000n, 400_000n, 1_000_000n, 5_000_000n]) {
  const q = await venue.quote({ tokenIn: usdc, tokenOut: eurc, amountIn: size, referencePrice: REFERENCE });
  let verdict = "pass";
  try {
    assertQuoteSane(q);
    if (size > largestSane) largestSane = size;
  } catch (error) {
    verdict = `refused (${(error as Error).message.split(" is ")[1] ?? "off market"})`;
  }
  console.log(
    `  ${(Number(size) / 1e6).toFixed(2).padStart(5)}  ${(Number(q.amountOut) / 1e6).toFixed(4).padStart(9)}` +
    `  ${String(q.deviationBps).padStart(6)} bps  ${verdict}`,
  );
}

if (largestSane === 0n) throw new Error("seeded a pool the wallet would refuse at every size");
console.log(`\n  the wallet will convert up to ${Number(largestSane) / 1e6} USDC against this pool`);
console.log(JSON.stringify({ chainId: CHAIN_ID, router, pair, usdc, eurc }, null, 2));
