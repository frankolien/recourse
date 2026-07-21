// Opens ONE disputed payment on a live deployment so the attestor bot can be demoed
// end to end (open dispute -> bot attests -> resolve -> verify). This is the buyer's
// half only: it funds a fresh buyer, pays once, and files a dispute, then STOPS with
// no attestation, leaving the payment in the Disputed state for the backend's
// POST /api/demo/attest and POST /api/demo/resolve to finish.
//
// The existing seeded payments cannot be reused: the seeder's buyer is a fresh random
// key that is never persisted, so we cannot sign fileDispute as them. This mints a new
// buyer we control instead.
//
// Usage:  node engine/scripts/open-dispute.mjs [deployments/arc-testnet.json]
// Env:    ARC_RPC_URL, DEPLOYER_PK (funds the buyer), SEED_BUYER_PK (optional pin),
//         DISPUTE_POLICY_ID (default 1), DISPUTE_CLAIM_TYPE (default 0).
//
// Runs against the real node via viem broadcast (Arc, or a local anvil deploy for a
// dry-run), never forge simulation (R13).

import { createWalletClient, createPublicClient, http, defineChain, keccak256 } from "viem";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const ARC = 5042002;

const deployArg = process.argv[2] ?? "deployments/arc-testnet.json";
const d = JSON.parse(readFileSync(resolve(repoRoot, deployArg), "utf8"));
const isLocal = d.chainId !== ARC;
// Default to dRPC on Arc: the official rpc.testnet.arc.network rate-limits hard.
const rpcUrl = process.env.ARC_RPC_URL ?? (isLocal ? "http://localhost:8545" : "https://arc-testnet.drpc.org");

const chain = defineChain({
  id: d.chainId,
  name: isLocal ? "anvil" : "arc-testnet",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [rpcUrl] } },
});

if (!process.env.DEPLOYER_PK && !isLocal) {
  console.error("DEPLOYER_PK required to fund the buyer on Arc");
  process.exit(1);
}
// Anvil deployer key for the local dry-run only; on Arc the real key comes from env.
const deployer = privateKeyToAccount(process.env.DEPLOYER_PK ?? "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
const buyer = privateKeyToAccount(process.env.SEED_BUYER_PK ?? generatePrivateKey());

const transport = http(rpcUrl, { retryCount: 12, retryDelay: 2000, timeout: 30000 });
const pub = createPublicClient({ chain, transport, pollingInterval: 4000 });
const wallet = (account) => createWalletClient({ account, chain, transport });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// The public Arc RPC returns "request limit reached" as a JSON-RPC error viem does not
// auto-retry, so back off explicitly (same policy as the seeder).
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
const ESCROW = [
  { type: "function", name: "pay", stateMutability: "nonpayable", inputs: [{ type: "uint256" }, { type: "uint128" }, { type: "bytes32" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "fileDispute", stateMutability: "nonpayable", inputs: [{ type: "uint256" }, { type: "uint8" }, { type: "tuple[]", components: [{ name: "evType", type: "uint8" }, { name: "hash", type: "bytes32" }] }], outputs: [] },
  { type: "function", name: "paymentCount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
];

const PAY = 250000n; // 0.25 USDC, matches the seeded payments
const policyId = BigInt(process.env.DISPUTE_POLICY_ID ?? 1);
const claimType = Number(process.env.DISPUTE_CLAIM_TYPE ?? 0);
const backendUrl = (process.env.BACKEND_URL ?? "http://localhost:8090").replace(/\/$/, "");

async function send(account, address, abi, functionName, args, label) {
  const hash = await withRetry(() => wallet(account).writeContract({ address, abi, functionName, args }), `${label} submit`);
  const rcpt = await withRetry(
    () => pub.waitForTransactionReceipt({ hash, pollingInterval: 6000, retryCount: 2, timeout: 120000 }),
    `${label} receipt`,
  );
  if (rcpt.status !== "success") throw new Error(`${label} reverted (${hash})`);
  await sleep(800);
  return rcpt;
}

const read = (address, abi, functionName, args) =>
  withRetry(() => pub.readContract({ address, abi, functionName, args }), `read ${functionName}`);

// Evidence to attach to the dispute. Content is arbitrary bytes; evType is the on-chain
// bit (PHOTO 1, DESCRIPTION 2, TRACKING_REF 4, VIDEO 8). The order here is the order the
// escrow folds items into evidenceRoot, so the manifest posted later must match it.
function disputeEvidence(paymentId) {
  const png1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+P+/HgAFhAJ/wlseKgAAAABJRU5ErkJggg==";
  return [
    { evType: 1, contentType: "image/png", bytes: Buffer.from(png1x1, "base64") },
    {
      evType: 2,
      contentType: "text/plain",
      bytes: Buffer.from(`Order ${paymentId}: item never arrived; tracking shows no movement since dispatch. Requesting full refund.`, "utf8"),
    },
  ];
}

// Stores a blob in the backend and returns its keccak256 hash, cross-checking the hash
// locally so we never pin on-chain a hash we did not verify ourselves.
async function uploadEvidence(bytes, contentType) {
  const res = await fetch(`${backendUrl}/api/evidence`, { method: "POST", headers: { "content-type": contentType }, body: bytes });
  if (!res.ok) throw new Error(`evidence upload failed (${res.status})`);
  const stored = await res.json();
  const local = keccak256(new Uint8Array(bytes));
  if (stored.hash.toLowerCase() !== local.toLowerCase()) {
    throw new Error(`evidence hash mismatch: store ${stored.hash} vs local ${local}`);
  }
  return stored.hash;
}

// Records the ordered evidence list; the backend accepts it only if its fold reproduces
// the onchain evidenceRoot we just set in fileDispute.
async function postManifest(paymentId, items) {
  const res = await fetch(`${backendUrl}/api/evidence/manifest`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ paymentId: Number(paymentId), items }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`manifest rejected (${res.status}): ${JSON.stringify(body)}`);
  return body;
}

async function main() {
  console.log(`opening a dispute on ${chain.name} (chainId ${d.chainId}) at ${rpcUrl}`);
  console.log(`  buyer ${buyer.address}`);
  const funding = PAY + 1_000000n; // payment plus gas headroom (USDC is the gas token on Arc)

  if (isLocal) {
    await send(deployer, d.usdc, USDC, "mint", [buyer.address, funding], "mint buyer");
  } else {
    await send(deployer, d.usdc, USDC, "transfer", [buyer.address, funding], "fund buyer");
  }
  await send(buyer, d.usdc, USDC, "approve", [d.escrow, funding], "buyer approve");

  const base = await read(d.escrow, ESCROW, "paymentCount");
  const paymentId = base + 1n;
  const orderRef = `0x${paymentId.toString(16).padStart(64, "0")}`;
  await send(buyer, d.escrow, ESCROW, "pay", [policyId, PAY, orderRef], "pay");

  // Upload evidence and pin it on-chain. If the backend is unreachable, fall back to an
  // empty dispute so the attestor-only demo still works.
  let items = [];
  try {
    for (const b of disputeEvidence(paymentId)) {
      const hash = await uploadEvidence(b.bytes, b.contentType);
      items.push({ evType: b.evType, hash });
      console.log(`  evidence ${b.contentType} -> ${hash}`);
    }
  } catch (e) {
    console.warn(`  evidence skipped: ${e.message ?? e}`);
    items = [];
  }
  const evidence = items.map((it) => ({ evType: it.evType, hash: it.hash }));
  await send(buyer, d.escrow, ESCROW, "fileDispute", [paymentId, claimType, evidence], "file dispute");

  if (items.length > 0) {
    const result = await postManifest(paymentId, items);
    console.log(`  manifest ${result.matches ? "VERIFIED" : "MISMATCH"} against onchain root ${result.onchainRoot}`);
  }

  console.log(`\nopened disputed paymentId ${paymentId} (policy ${policyId}, claimType ${claimType}, status Disputed)`);
  if (items.length > 0) {
    console.log(`  evidence: ${items.length} item(s), view: GET ${backendUrl}/api/payments/${paymentId}/evidence`);
  }
  console.log(`finish it with the attestor bot:`);
  console.log(`  curl -X POST ${backendUrl}/api/demo/attest  -H 'content-type: application/json' -d '{"paymentId":${paymentId},"value":2}'`);
  console.log(`  curl -X POST ${backendUrl}/api/demo/resolve -H 'content-type: application/json' -d '{"paymentId":${paymentId}}'`);
  console.log(`then verify at /verify/${paymentId}`);
}

main().catch((e) => {
  console.error(e.message ?? e);
  process.exit(1);
});
