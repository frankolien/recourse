// Runnable attestor. Wires the daemon in src/attestor-daemon.ts to a real chain and
// a real evidence host, and does nothing else: every decision about what may be
// signed lives in that module and is tested against fakes.
//
//   ops/attestor.sh                          # against Arc, from deployments
//   ATTESTOR_RPC=... ops/attestor.sh --once  # one sweep and exit
//
// The signing key is read from the environment and never logged.

import { createPublicClient, createWalletClient, defineChain, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { runDaemon, sweepOnce } from "../src/attestor-daemon";
import type { AttestorChain, AttestorDeps } from "../src/attestor-daemon";

const need = (name: string): string => {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
};

const RPC = need("ATTESTOR_RPC");
const CHAIN_ID = Number(need("ATTESTOR_CHAIN_ID"));
const ESCROW = need("ATTESTOR_ESCROW") as `0x${string}`;
const EVIDENCE_BASE = need("ATTESTOR_EVIDENCE_URL").replace(/\/$/, "");
const KEY = need("ATTESTOR_KEY") as `0x${string}`;
const LOOKBACK = BigInt(process.env.ATTESTOR_LOOKBACK ?? "9000");
const INTERVAL_MS = Number(process.env.ATTESTOR_INTERVAL_MS ?? 15_000);
const ONCE = process.argv.includes("--once");

const chainDef = defineChain({
  id: CHAIN_ID,
  name: `chain-${CHAIN_ID}`,
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [RPC] } },
});

const abi = parseAbi([
  "function getPayment(uint256 paymentId) view returns ((address buyer, address merchant, address beneficiary, uint256 policyId, uint128 amount, uint128 shares, uint64 paidAt, uint64 filedAt, uint8 claimType, uint16 evidenceMask, uint8 attType, uint8 attValue, bytes32 evidenceRoot, uint16 verdictBps, uint8 status))",
  "function attestorFor(uint256 policyId) view returns (address)",
  "function attestationDigest(uint256 paymentId, uint8 attType, uint8 value, uint64 deadline) view returns (bytes32)",
  "function submitAttestation(uint256 paymentId, uint8 attType, uint8 value, uint64 deadline, bytes sig)",
  "event DisputeFiled(uint256 indexed paymentId, uint8 claimType, uint16 evidenceMask, bytes32 evidenceRoot)",
  "event Paid(uint256 indexed paymentId, address indexed buyer, address indexed merchant, uint256 policyId, uint128 amount, bytes32 orderRef, bytes32 policyHash)",
]);

const account = privateKeyToAccount(KEY);
const publicClient = createPublicClient({ chain: chainDef, transport: http(RPC) });
const walletClient = createWalletClient({ account, chain: chainDef, transport: http(RPC) });

// Bounded windows throughout: public RPC providers cap eth_getLogs ranges, and an
// unbounded query fails outright on any chain with real history.
async function window(): Promise<{ fromBlock: bigint; toBlock: "latest" }> {
  const head = await publicClient.getBlockNumber();
  return { fromBlock: head > LOOKBACK ? head - LOOKBACK : 0n, toBlock: "latest" };
}

const chain: AttestorChain = {
  async recentDisputes() {
    const logs = await publicClient.getContractEvents({
      address: ESCROW, abi, eventName: "DisputeFiled", ...(await window()),
    });
    return [...new Set(logs.map((l) => l.args.paymentId as bigint))];
  },
  async getPayment(paymentId) {
    const p = await publicClient.readContract({ address: ESCROW, abi, functionName: "getPayment", args: [paymentId] });
    if (p.status === 0) return null;
    return {
      paymentId,
      policyId: p.policyId,
      evidenceRoot: p.evidenceRoot,
      claimType: p.claimType,
      attType: p.attType,
      status: p.status,
    };
  },
  async orderRef(paymentId) {
    const logs = await publicClient.getContractEvents({
      address: ESCROW, abi, eventName: "Paid", args: { paymentId }, ...(await window()),
    });
    return (logs[0]?.args.orderRef as `0x${string}`) ?? null;
  },
  attestorFor: (policyId) =>
    publicClient.readContract({ address: ESCROW, abi, functionName: "attestorFor", args: [policyId] }),
  attestationDigest: (paymentId, attType, value, deadline) =>
    publicClient.readContract({
      address: ESCROW, abi, functionName: "attestationDigest", args: [paymentId, attType, value, deadline],
    }),
  async submitAttestation(paymentId, attType, value, deadline, signature) {
    const hash = await walletClient.writeContract({
      address: ESCROW, abi, functionName: "submitAttestation",
      args: [paymentId, attType, value, deadline, signature],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    return hash;
  },
};

const deps: AttestorDeps = {
  chain,
  async fetchSession(sessionId) {
    const response = await fetch(`${EVIDENCE_BASE}/session/${sessionId}`);
    if (!response.ok) throw new Error(`evidence host returned ${response.status}`);
    return response.json();
  },
  sign: (digest) => account.sign({ hash: digest }),
  self: account.address,
  // Read from the chain rather than the local clock: the escrow validates the
  // deadline against block.timestamp.
  nowSeconds: async () => Number((await publicClient.getBlock()).timestamp),
  log: (line) => console.log(`[attestor] ${line}`),
};

console.log(`[attestor] ${account.address} watching ${ESCROW} on chain ${CHAIN_ID}`);
console.log(`[attestor] evidence host ${EVIDENCE_BASE}`);

if (ONCE) {
  const summary = await sweepOnce(deps);
  console.log(`[attestor] seen ${summary.seen}, attested ${summary.attested.length}, skipped ${summary.skipped.length}`);
} else {
  const controller = new AbortController();
  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.on(signal, () => {
      console.log("[attestor] stopping");
      controller.abort();
    });
  }
  await runDaemon(deps, { intervalMs: INTERVAL_MS, signal: controller.signal });
}
