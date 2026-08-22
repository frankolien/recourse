// The one place the attestor is wired to a real chain and a real evidence host.
//
// Shared by the local runner (attestor.ts) and the hosted service
// (attestor-service.ts) so the two cannot drift: every decision about what may be
// signed lives in src/attestor-daemon.ts and is tested against fakes, and
// everything here is transport.

import { readFileSync } from "node:fs";
import { createPublicClient, createWalletClient, defineChain, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { AttestorChain, AttestorDeps } from "../src/attestor-daemon";

export interface AttestorConfig {
  rpc: string;
  chainId: number;
  escrow: `0x${string}`;
  evidenceBase: string;
  lookback: bigint;
  intervalMs: number;
}

export function configFromEnv(env: NodeJS.ProcessEnv = process.env): AttestorConfig {
  // Addresses come from the deployment record rather than the image (R3). Env still
  // wins, so a single service can be pointed at anvil without rebuilding.
  let deployment: { chainId?: number; escrow?: string } = {};
  if (env.ATTESTOR_DEPLOYMENT) {
    deployment = JSON.parse(readFileSync(env.ATTESTOR_DEPLOYMENT, "utf8"));
  }

  const need = (name: string, fallback?: string | number): string => {
    const value = env[name] ?? (fallback === undefined ? undefined : String(fallback));
    if (!value) throw new Error(`${name} is required`);
    return value;
  };
  return {
    rpc: need("ATTESTOR_RPC"),
    chainId: Number(need("ATTESTOR_CHAIN_ID", deployment.chainId)),
    escrow: need("ATTESTOR_ESCROW", deployment.escrow) as `0x${string}`,
    evidenceBase: need("ATTESTOR_EVIDENCE_URL").replace(/\/$/, ""),
    lookback: BigInt(env.ATTESTOR_LOOKBACK ?? "9000"),
    intervalMs: Number(env.ATTESTOR_INTERVAL_MS ?? 15_000),
  };
}

const abi = parseAbi([
  "function getPayment(uint256 paymentId) view returns ((address buyer, address merchant, address beneficiary, uint256 policyId, uint128 amount, uint128 shares, uint64 paidAt, uint64 filedAt, uint8 claimType, uint16 evidenceMask, uint8 attType, uint8 attValue, bytes32 evidenceRoot, uint16 verdictBps, uint8 status))",
  "function attestorFor(uint256 policyId) view returns (address)",
  "function attestationDigest(uint256 paymentId, uint8 attType, uint8 value, uint64 deadline) view returns (bytes32)",
  "function submitAttestation(uint256 paymentId, uint8 attType, uint8 value, uint64 deadline, bytes sig)",
  "event DisputeFiled(uint256 indexed paymentId, uint8 claimType, uint16 evidenceMask, bytes32 evidenceRoot)",
  "event Paid(uint256 indexed paymentId, address indexed buyer, address indexed merchant, uint256 policyId, uint128 amount, bytes32 orderRef, bytes32 policyHash)",
]);

export interface Wiring {
  deps: AttestorDeps;
  address: `0x${string}`;
  config: AttestorConfig;
}

/** The signing key is read here and never logged or returned. */
export function buildAttestor(config: AttestorConfig, key: `0x${string}`): Wiring {
  const chainDef = defineChain({
    id: config.chainId,
    name: `chain-${config.chainId}`,
    nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
    rpcUrls: { default: { http: [config.rpc] } },
  });

  const account = privateKeyToAccount(key);
  const publicClient = createPublicClient({ chain: chainDef, transport: http(config.rpc) });
  const walletClient = createWalletClient({ account, chain: chainDef, transport: http(config.rpc) });

  // Bounded windows throughout: public RPC providers cap eth_getLogs ranges, and an
  // unbounded query fails outright on any chain with real history.
  async function window(): Promise<{ fromBlock: bigint; toBlock: "latest" }> {
    const head = await publicClient.getBlockNumber();
    return { fromBlock: head > config.lookback ? head - config.lookback : 0n, toBlock: "latest" };
  }

  const chain: AttestorChain = {
    async recentDisputes() {
      const logs = await publicClient.getContractEvents({
        address: config.escrow, abi, eventName: "DisputeFiled", ...(await window()),
      });
      return [...new Set(logs.map((l) => l.args.paymentId as bigint))];
    },
    async getPayment(paymentId) {
      const p = await publicClient.readContract({
        address: config.escrow, abi, functionName: "getPayment", args: [paymentId],
      });
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
        address: config.escrow, abi, eventName: "Paid", args: { paymentId }, ...(await window()),
      });
      return (logs[0]?.args.orderRef as `0x${string}`) ?? null;
    },
    attestorFor: (policyId) =>
      publicClient.readContract({ address: config.escrow, abi, functionName: "attestorFor", args: [policyId] }),
    attestationDigest: (paymentId, attType, value, deadline) =>
      publicClient.readContract({
        address: config.escrow, abi, functionName: "attestationDigest", args: [paymentId, attType, value, deadline],
      }),
    async submitAttestation(paymentId, attType, value, deadline, signature) {
      const hash = await walletClient.writeContract({
        address: config.escrow, abi, functionName: "submitAttestation",
        args: [paymentId, attType, value, deadline, signature],
      });
      await publicClient.waitForTransactionReceipt({ hash });
      return hash;
    },
  };

  const deps: AttestorDeps = {
    chain,
    // Over HTTP even when the evidence host runs in this same process. The attestor
    // is not entitled to privileged access to the evidence, and keeping the fetch
    // identical in both deployments means splitting them later changes nothing.
    async fetchSession(sessionId) {
      const response = await fetch(`${config.evidenceBase}/session/${sessionId}`);
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

  return { deps, address: account.address, config };
}
