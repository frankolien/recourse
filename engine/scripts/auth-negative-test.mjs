// Focused negative integration test for buyer-signature auth. A structurally valid EIP-712
// authorization (signature recovers to walletAddress) signed by a wallet that is NOT the
// payment's on-chain buyer must be rejected with 403, must persist nothing, and must not
// consume its nonce. This exercises the `recovered != payment.buyer` branch that the unit
// tests cannot reach (they stop at signature recovery).
//
// No funds move: it only reads getPayment and makes failing writes. Run against a live
// backend and Arc.
//
// Usage:  node engine/scripts/auth-negative-test.mjs [deployments/arc-testnet.json]
// Env:    BACKEND_URL (default http://localhost:8090), TARGET_PAYMENT_ID (default 11),
//         ARC_RPC_URL (default dRPC). Exits non-zero on any failed assertion. It prints
//         the two nonces it used so the caller can confirm in Postgres that neither was
//         consumed (SELECT consumed FROM auth_challenges WHERE nonce IN (...)).

import { createPublicClient, http, defineChain, keccak256 } from "viem";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const ARC = 5042002;

const deployArg = process.argv[2] ?? "deployments/arc-testnet.json";
const d = JSON.parse(readFileSync(resolve(repoRoot, deployArg), "utf8"));
const backendUrl = (process.env.BACKEND_URL ?? "http://localhost:8090").replace(/\/$/, "");
const paymentId = Number(process.env.TARGET_PAYMENT_ID ?? 11);
const isLocal = d.chainId !== ARC;
const rpcUrl = process.env.ARC_RPC_URL ?? (isLocal ? "http://localhost:8545" : "https://arc-testnet.drpc.org");

const chain = defineChain({
  id: d.chainId,
  name: isLocal ? "anvil" : "arc-testnet",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [rpcUrl] } },
});
const pub = createPublicClient({ chain, transport: http(rpcUrl, { retryCount: 6, retryDelay: 2000 }) });

// A wallet that owns nothing: it is not the buyer of any payment.
const attacker = privateKeyToAccount(generatePrivateKey());

const AUTH_TYPES = {
  Authorization: [
    { name: "action", type: "string" },
    { name: "paymentId", type: "uint256" },
    { name: "walletAddress", type: "address" },
    { name: "chainId", type: "uint256" },
    { name: "bodyHash", type: "bytes32" },
    { name: "nonce", type: "bytes32" },
    { name: "expiresAt", type: "uint256" },
  ],
};

const ESCROW = [
  {
    type: "function",
    name: "getPayment",
    stateMutability: "view",
    inputs: [{ type: "uint256" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "buyer", type: "address" },
          { name: "merchant", type: "address" },
          { name: "beneficiary", type: "address" },
          { name: "policyId", type: "uint256" },
          { name: "amount", type: "uint128" },
          { name: "shares", type: "uint128" },
          { name: "paidAt", type: "uint64" },
          { name: "filedAt", type: "uint64" },
          { name: "claimType", type: "uint8" },
          { name: "evidenceMask", type: "uint16" },
          { name: "attType", type: "uint8" },
          { name: "attValue", type: "uint8" },
          { name: "evidenceRoot", type: "bytes32" },
          { name: "verdictBps", type: "uint16" },
          { name: "status", type: "uint8" },
        ],
      },
    ],
  },
];

let failures = 0;
function check(label, ok, detail = "") {
  console.log(`  ${ok ? "PASS" : "FAIL"}  ${label}${detail ? ` (${detail})` : ""}`);
  if (!ok) failures++;
}

async function challenge() {
  const res = await fetch(`${backendUrl}/api/auth/challenge`, { method: "POST" });
  if (!res.ok) throw new Error(`challenge failed (${res.status})`);
  return res.json();
}

// A structurally valid envelope: the signature recovers to walletAddress. It is only wrong
// in that walletAddress is the attacker, not the payment's buyer.
async function attackerAuth(action, bodyBytes) {
  const { nonce, expiresAt } = await challenge();
  const bodyHash = keccak256(new Uint8Array(bodyBytes));
  const signature = await attacker.signTypedData({
    domain: { name: "Recourse", version: "1", chainId: d.chainId },
    types: AUTH_TYPES,
    primaryType: "Authorization",
    message: {
      action,
      paymentId: BigInt(paymentId),
      walletAddress: attacker.address,
      chainId: BigInt(d.chainId),
      bodyHash,
      nonce,
      expiresAt: BigInt(expiresAt),
    },
  });
  const envelope = {
    action,
    paymentId,
    walletAddress: attacker.address,
    chainId: d.chainId,
    bodyHash,
    nonce,
    expiresAt,
    signature,
  };
  return { header: Buffer.from(JSON.stringify(envelope)).toString("base64"), nonce, bodyHash };
}

async function main() {
  console.log(`auth negative test against ${backendUrl}, payment ${paymentId}, attacker ${attacker.address}`);
  const payment = await pub.readContract({ address: d.escrow, abi: ESCROW, functionName: "getPayment", args: [BigInt(paymentId)] });
  if (payment.policyId === 0n) throw new Error(`payment ${paymentId} does not exist on chain; pick an existing TARGET_PAYMENT_ID`);
  if (payment.buyer.toLowerCase() === attacker.address.toLowerCase()) throw new Error("attacker is the buyer; regenerate");
  console.log(`  payment ${paymentId} buyer is ${payment.buyer} (not the attacker)`);

  // 1. Wrong-wallet evidence upload. Unique bytes so a 404 afterwards proves non-storage.
  const uniqueBody = Buffer.from(`recourse auth negative test ${attacker.address} ${paymentId}`, "utf8");
  const up = await attackerAuth("evidence.upload", uniqueBody);
  const upRes = await fetch(`${backendUrl}/api/evidence`, {
    method: "POST",
    headers: { "content-type": "text/plain", "x-recourse-auth": up.header },
    body: uniqueBody,
  });
  check("wrong-wallet evidence upload is rejected 403", upRes.status === 403, `got ${upRes.status}`);
  const blobRes = await fetch(`${backendUrl}/api/evidence/${up.bodyHash}`);
  check("uploaded blob was NOT persisted (404)", blobRes.status === 404, `got ${blobRes.status}`);

  // 2. Wrong-wallet manifest with a bogus item that must not overwrite the real one.
  const bogusHash = `0x${"11".repeat(32)}`;
  const bodyStr = JSON.stringify({ paymentId, items: [{ evType: 1, hash: bogusHash }] });
  const man = await attackerAuth("evidence.manifest", Buffer.from(bodyStr, "utf8"));
  const manRes = await fetch(`${backendUrl}/api/evidence/manifest`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-recourse-auth": man.header },
    body: bodyStr,
  });
  check("wrong-wallet manifest is rejected 403", manRes.status === 403, `got ${manRes.status}`);
  const ev = await (await fetch(`${backendUrl}/api/payments/${paymentId}/evidence`)).json();
  const bogusPresent = Array.isArray(ev.items) && ev.items.some((it) => it.hash?.toLowerCase() === bogusHash);
  check("manifest was NOT overwritten (bogus item absent, chain match holds)", !bogusPresent && ev.matches === true, `matches=${ev.matches}, items=${ev.items?.length}`);

  console.log(`\nnonces used (confirm consumed=false in Postgres):`);
  console.log(`  upload   ${up.nonce}`);
  console.log(`  manifest ${man.nonce}`);

  if (failures > 0) {
    console.error(`\n${failures} assertion(s) FAILED`);
    process.exit(1);
  }
  console.log(`\nall assertions passed`);
}

main().catch((e) => {
  console.error(e.message ?? e);
  process.exit(1);
});
