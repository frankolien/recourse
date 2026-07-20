// Seeds demo state on a live deployment via viem (direct RPC broadcast).
//
// Arc's USDC is a native-token precompile, so `forge script` cannot execute the
// USDC-moving calls in its local EVM (StackUnderflow). viem broadcasts real
// transactions that the Arc node executes natively, so this is the seeder for Arc.
// It also runs against a local anvil deployment (plain ERC-20 USDC) for dry-runs.
//
// Usage:  node engine/scripts/seed.mjs [deployments/arc-testnet.json]
// Env:    ARC_RPC_URL (Arc), DEPLOYER_PK (also the attestor), SEED_MERCHANT_PK,
//         SEED_BUYER_PK. Keys default to anvil accounts for the local dry-run.
//
// Produces: one merchant policy, eight payments, two disputes attested to opposite
// verdicts (NOT_DELIVERED -> full refund, DELIVERED -> denied), one vault advance.

import { createWalletClient, createPublicClient, http, defineChain } from "viem";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const ARC = 5042002;

const ANVIL = {
  deployer: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  merchant: "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  buyer: "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
};

const deployArg = process.argv[2] ?? "deployments/arc-testnet.json";
const deployPath = resolve(repoRoot, deployArg);
const d = JSON.parse(readFileSync(deployPath, "utf8"));
const isLocal = d.chainId !== ARC;
const rpcUrl = process.env.ARC_RPC_URL ?? (isLocal ? "http://localhost:8545" : "https://rpc.testnet.arc.network");

const chain = defineChain({
  id: d.chainId,
  name: isLocal ? "anvil" : "arc-testnet",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [rpcUrl] } },
});

// Anvil keys are pre-funded with gas locally, but some are on Arc USDC's blocklist,
// so on Arc default the buyer and merchant to fresh random keys (funded in-script).
const seedKey = (envName, anvilKey) =>
  process.env[envName] ?? (isLocal ? anvilKey : generatePrivateKey());
const deployer = privateKeyToAccount(process.env.DEPLOYER_PK ?? ANVIL.deployer);
const merchant = privateKeyToAccount(seedKey("SEED_MERCHANT_PK", ANVIL.merchant));
const buyer = privateKeyToAccount(seedKey("SEED_BUYER_PK", ANVIL.buyer));

// The public Arc RPC rate-limits, so retry with backoff and poll receipts gently.
const transport = http(rpcUrl, { retryCount: 12, retryDelay: 2000, timeout: 30000 });
const pub = createPublicClient({ chain, transport, pollingInterval: 4000 });
const wallet = (account) => createWalletClient({ account, chain, transport });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Explicit retry: the public RPC returns "request limit reached" as a JSON-RPC error,
// which viem's transport does not treat as retryable, so back off and retry here.
async function withRetry(fn, label, attempts = 10) {
  for (let i = 0; ; i++) {
    try {
      return await fn();
    } catch (e) {
      const msg = e?.message ? e.message : String(e);
      const retryable = /limit|429|timeout|fetch failed|ECONN|socket|network/i.test(msg);
      if (!retryable || i >= attempts - 1) throw e;
      const wait = Math.min(20000, 1500 * 2 ** i) + Math.floor(Math.random() * 800);
      console.log(`  ${label}: rate-limited, retry ${i + 1} in ${Math.round(wait / 1000)}s`);
      await sleep(wait);
    }
  }
}

const USDC = [
  { type: "function", name: "transfer", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "mint", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [] },
];
const RULE = { type: "tuple", components: [
  { name: "claimType", type: "uint8" }, { name: "requiredEvidenceMask", type: "uint16" },
  { name: "attType", type: "uint8" }, { name: "attExpected", type: "uint8" },
  { name: "claimWindow", type: "uint32" }, { name: "refundBps", type: "uint16" }, { name: "requiresReturn", type: "bool" },
] };
const REGISTRY = [
  { type: "function", name: "registerPolicy", stateMutability: "nonpayable", inputs: [{ type: "uint32" }, { type: "uint16" }, { ...RULE, type: "tuple[]", name: "rules" }, { type: "string" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "policyCount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
];
const ESCROW = [
  { type: "function", name: "pay", stateMutability: "nonpayable", inputs: [{ type: "uint256" }, { type: "uint128" }, { type: "bytes32" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "fileDispute", stateMutability: "nonpayable", inputs: [{ type: "uint256" }, { type: "uint8" }, { type: "tuple[]", components: [{ name: "evType", type: "uint8" }, { name: "hash", type: "bytes32" }] }], outputs: [] },
  { type: "function", name: "submitAttestation", stateMutability: "nonpayable", inputs: [{ type: "uint256" }, { type: "uint8" }, { type: "uint8" }, { type: "uint64" }, { type: "bytes" }], outputs: [] },
  { type: "function", name: "resolve", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [] },
  { type: "function", name: "paymentCount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "previewVerdict", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "tuple", components: [{ name: "refundBps", type: "uint16" }, { name: "requiresReturn", type: "bool" }, { name: "ruleIndex", type: "uint8" }, { name: "matched", type: "bool" }] }, { type: "bytes32" }] },
];
const VAULT = [
  { type: "function", name: "enrollMerchant", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint16" }, { type: "uint128" }], outputs: [] },
  { type: "function", name: "deposit", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "advance", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [] },
];

const N = 8n;
const PAY = 250000n; // 0.25 USDC, kept small so re-runs are cheap on testnet
const DAY = 86400;

async function send(account, address, abi, functionName, args, label) {
  const hash = await withRetry(() => wallet(account).writeContract({ address, abi, functionName, args }), `${label} submit`);
  const rcpt = await withRetry(
    () => pub.waitForTransactionReceipt({ hash, pollingInterval: 6000, retryCount: 2, timeout: 120000 }),
    `${label} receipt`,
  );
  if (rcpt.status !== "success") throw new Error(`${label} reverted (${hash})`);
  await sleep(800); // stay under the public RPC rate limit
  return rcpt;
}

const read = (address, abi, functionName, args) =>
  withRetry(() => pub.readContract({ address, abi, functionName, args }), `read ${functionName}`);

const rules = [
  { claimType: 0, requiredEvidenceMask: 0, attType: 1, attExpected: 2, claimWindow: 14 * DAY, refundBps: 10000, requiresReturn: false },
  { claimType: 1, requiredEvidenceMask: 1, attType: 0, attExpected: 0, claimWindow: 3 * DAY, refundBps: 10000, requiresReturn: true },
];

async function attestAndResolve(id, value) {
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
  const signature = await deployer.signTypedData({
    domain: { name: "RecourseAttestor", version: "1", chainId: d.chainId, verifyingContract: d.escrow },
    types: { Attestation: [{ name: "paymentId", type: "uint256" }, { name: "attType", type: "uint8" }, { name: "value", type: "uint8" }, { name: "deadline", type: "uint64" }] },
    primaryType: "Attestation",
    message: { paymentId: id, attType: 1, value, deadline },
  });
  await send(deployer, d.escrow, ESCROW, "submitAttestation", [id, 1, value, deadline, signature], `attest ${id}`);
  await send(deployer, d.escrow, ESCROW, "resolve", [id], `resolve ${id}`);
}

async function main() {
  console.log(`seeding ${chain.name} (chainId ${d.chainId}) at ${rpcUrl}`);
  console.log(`  merchant ${merchant.address}`);
  console.log(`  buyer    ${buyer.address}`);
  const buyerFunding = PAY * N + 1_000000n; // payments + gas headroom
  const lpDeposit = 2_000000n;

  // Phase 1: deployer funds actors, enrolls the merchant, seeds the vault.
  if (isLocal) {
    await send(deployer, d.usdc, USDC, "mint", [buyer.address, buyerFunding], "mint buyer");
    await send(deployer, d.usdc, USDC, "mint", [deployer.address, lpDeposit], "mint deployer");
  } else {
    await send(deployer, d.usdc, USDC, "transfer", [buyer.address, buyerFunding], "fund buyer");
    await send(deployer, d.usdc, USDC, "transfer", [merchant.address, 500000n], "fund merchant gas");
  }
  await send(deployer, d.settlementVault, VAULT, "enrollMerchant", [merchant.address, 50, 100_000000n], "enroll merchant");
  await send(deployer, d.usdc, USDC, "approve", [d.settlementVault, lpDeposit], "lp approve");
  await send(deployer, d.settlementVault, VAULT, "deposit", [lpDeposit], "lp deposit");

  // Phase 2: merchant publishes a policy.
  await send(merchant, d.policyRegistry, REGISTRY, "registerPolicy", [14 * DAY, 0, rules, "ipfs://demo-policy"], "register policy");
  const policyId = await read(d.policyRegistry, REGISTRY, "policyCount");

  // Phase 3: buyer pays eight times and disputes two. paymentIds are sequential from
  // the current count, so read it once instead of after every pay (fewer RPC calls).
  await send(buyer, d.usdc, USDC, "approve", [d.escrow, buyerFunding], "buyer approve");
  const base = await read(d.escrow, ESCROW, "paymentCount");
  const ids = [];
  for (let i = 0n; i < N; i++) {
    await send(buyer, d.escrow, ESCROW, "pay", [policyId, PAY, `0x${(i + 1n).toString(16).padStart(64, "0")}`], `pay ${i}`);
    ids.push(base + i + 1n);
  }
  await send(buyer, d.escrow, ESCROW, "fileDispute", [ids[4], 0, []], "dispute refund");
  await send(buyer, d.escrow, ESCROW, "fileDispute", [ids[5], 0, []], "dispute deny");

  // Phase 4: attestor resolves to opposite verdicts; the vault advances a payment.
  await attestAndResolve(ids[4], 2); // NOT_DELIVERED -> full refund
  await attestAndResolve(ids[5], 1); // DELIVERED -> denied
  await send(deployer, d.settlementVault, VAULT, "advance", [ids[6]], "advance");

  const pointers = {
    policyId: Number(policyId),
    merchant: merchant.address,
    buyer: buyer.address,
    refundPaymentId: Number(ids[4]),
    denyPaymentId: Number(ids[5]),
    advancedPaymentId: Number(ids[6]),
    openPaymentIds: [ids[0], ids[1], ids[2], ids[3], ids[7]].map(Number),
  };
  const outName = isLocal ? `seed-local-${d.chainId}.json` : "seed-arc-testnet.json";
  writeFileSync(resolve(repoRoot, "deployments", outName), JSON.stringify(pointers, null, 2) + "\n");

  const [refundVerdict] = await read(d.escrow, ESCROW, "previewVerdict", [ids[4]]);
  console.log("policyId", pointers.policyId);
  console.log("refund paymentId", pointers.refundPaymentId, "verdict", refundVerdict);
  console.log("deny paymentId", pointers.denyPaymentId);
  console.log("advanced paymentId", pointers.advancedPaymentId);
  console.log(`wrote deployments/${outName}`);
}

main().catch((e) => {
  console.error(e.message ?? e);
  process.exit(1);
});
