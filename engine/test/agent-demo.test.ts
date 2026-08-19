// One agent buying inference from another, end to end, docs/agent-settlement.md
// section A5. Real HTTP over a real socket, real contracts on a real node.
//
// Doubles as the demo, which is why it narrates. Run it with:
//   ops/agent-demo.sh
// or against a node you started yourself:
//   DEMO_RPC=http://127.0.0.1:8545 npx vitest run test/agent-demo.test.ts
//
// Skipped when DEMO_RPC is unset, so the default suite stays offline.

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { createServer, type Server } from "node:http";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  createPublicClient,
  createWalletClient,
  defineChain,
  http,
  keccak256,
  parseAbi,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

import { agentServicePolicy, severity } from "../src/agent";
import { SessionRecorder } from "../src/session";
import { reviewSession } from "../src/attestor";
import { sweepOnce } from "../src/attestor-daemon";
import type { AttestorChain, AttestorDeps } from "../src/attestor-daemon";
import { AgentClaimType, AgentEvidence, ATT_SLA_OUTCOME, SlaOutcome } from "../src/types";
import {
  buildPaymentHeader,
  parseQuote,
  quote,
  quoteHeader,
  verify,
  verifyTerms,
  PAYMENT_REQUIRED_HEADER,
  PAYMENT_SIGNATURE_HEADER,
  EscrowStatus,
  type EscrowReader,
  type QuoteOptions,
} from "../src/x402";

const RPC = process.env.DEMO_RPC;
const suite = RPC ? describe : describe.skip;

// Dual target. With no overrides this deploys everything onto a throwaway anvil
// node; against Arc it reuses the registry and yield adapter already deployed
// there and only the escrow is new, so nothing in deployments/arc-testnet.json
// has to move.
const CHAIN_ID = Number(process.env.DEMO_CHAIN_ID ?? 31337);
const LIVE = CHAIN_ID !== 31337;
const EXISTING_USDC = process.env.DEMO_USDC as Address | undefined;
const EXISTING_REGISTRY = process.env.DEMO_REGISTRY as Address | undefined;
const EXISTING_ADAPTER = process.env.DEMO_ADAPTER as Address | undefined;

// anvil's first three deterministic accounts. Publicly known on purpose: on a
// testnet they hold nothing worth stealing, and using them creates no new secret.
const KEYS = {
  merchant: (process.env.DEMO_DEPLOYER_PK ??
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80") as Hex,
  buyer: (process.env.DEMO_BUYER_PK ??
    "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d") as Hex,
  attestor: (process.env.DEMO_ATTESTOR_PK ??
    "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a") as Hex,
} as const;

// Reuse an escrow and policy from an earlier run rather than deploying again.
const EXISTING_ESCROW = process.env.DEMO_ESCROW as Address | undefined;
const EXISTING_POLICY = process.env.DEMO_POLICY_ID ? BigInt(process.env.DEMO_POLICY_ID) : undefined;

const here = dirname(fileURLToPath(import.meta.url));
const artifact = (name: string) =>
  JSON.parse(readFileSync(join(here, `../../contracts/out/${name}.sol/${name}.json`), "utf8"));

const anvil = defineChain({
  id: CHAIN_ID,
  name: LIVE ? "Arc" : "Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC ?? "http://127.0.0.1:8545"] } },
});

const escrowAbi = parseAbi([
  "function pay(uint256 policyId, uint128 amount, bytes32 orderRef) returns (uint256)",
  "function fileDispute(uint256 paymentId, uint8 claimType, (uint8 evType, bytes32 hash)[] evidence)",
  "function submitAttestation(uint256 paymentId, uint8 attType, uint8 value, uint64 deadline, bytes sig)",
  "function resolve(uint256 paymentId)",
  "function release(uint256 paymentId)",
  "function setPolicyAttestor(uint256 policyId, address a)",
  "function attestorFor(uint256 policyId) view returns (address)",
  "function agreementHash(uint256 policyId) view returns (bytes32)",
  "function attestationDigest(uint256 paymentId, uint8 attType, uint8 value, uint64 deadline) view returns (bytes32)",
  "function getPayment(uint256 paymentId) view returns ((address buyer, address merchant, address beneficiary, uint256 policyId, uint128 amount, uint128 shares, uint64 paidAt, uint64 filedAt, uint8 claimType, uint16 evidenceMask, uint8 attType, uint8 attValue, bytes32 evidenceRoot, uint16 verdictBps, uint8 status))",
  "event Paid(uint256 indexed paymentId, address indexed buyer, address indexed merchant, uint256 policyId, uint128 amount, bytes32 orderRef, bytes32 policyHash)",
]);
const registryAbi = parseAbi([
  "function policyCount() view returns (uint256)",
  "function registerPolicy(uint32 disputeWindow, uint16 defaultRefundBps, (uint8 claimType, uint16 requiredEvidenceMask, uint8 attType, uint8 attExpected, uint32 claimWindow, uint16 refundBps, bool requiresReturn)[] rules, string metadataURI) returns (uint256)",
  "function policyHash(uint256 policyId) view returns (bytes32)",
  "function getPolicy(uint256 policyId) view returns ((address merchant, uint32 disputeWindow, uint16 defaultRefundBps, (uint8 claimType, uint16 requiredEvidenceMask, uint8 attType, uint8 attExpected, uint32 claimWindow, uint16 refundBps, bool requiresReturn)[] rules))",
]);
const usdcAbi = parseAbi([
  "function mint(address to, uint256 amount)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function balanceOf(address a) view returns (uint256)",
]);

// Short enough on a live chain that scenario A can wait the window out for real.
const DISPUTE_WINDOW = Number(process.env.DEMO_DISPUTE_WINDOW ?? (LIVE ? 90 : 3600));
const BUDGET = BigInt(process.env.DEMO_BUDGET ?? (LIVE ? 200_000n : 5_000_000n));
const log = (line: string) => console.log(line);
const usd = (v: bigint) => `${(Number(v) / 1e6).toFixed(2)} USDC`;

suite("agent buys from agent", () => {
  const publicClient = createPublicClient({ chain: anvil, transport: http(RPC) });
  const merchant = privateKeyToAccount(KEYS.merchant);
  const buyer = privateKeyToAccount(KEYS.buyer);
  const attestor = privateKeyToAccount(KEYS.attestor);
  const wallet = (account: typeof merchant) => createWalletClient({ account, chain: anvil, transport: http(RPC) });

  let usdc: Address;
  let registry: Address;
  let escrow: Address;
  let policyId: bigint;
  let server: Server;
  let origin: string;
  // The buyer's evidence host. Separate from the seller so the attestor is
  // demonstrably fetching published bytes rather than reading anyone's memory.
  let evidenceServer: Server;
  let evidenceOrigin: string;
  const publishedSessions = new Map<string, unknown>();

  // The service succeeds on every Nth call and fails the rest, so a scenario lands
  // on an exact failure ratio rather than an approximate one. 1 means never fail.
  let succeedEvery = 1;
  let served = 0;

  async function deploy(name: string, args: unknown[]): Promise<Address> {
    const a = artifact(name);
    const hash = await wallet(merchant).deployContract({ abi: a.abi, bytecode: a.bytecode.object as Hex, args });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    return receipt.contractAddress!;
  }

  const reader: EscrowReader = {
    async getPayment(paymentId) {
      const p = await publicClient.readContract({
        address: escrow, abi: escrowAbi, functionName: "getPayment", args: [paymentId],
      });
      return p.status === 0 ? null : {
        buyer: p.buyer, merchant: p.merchant, policyId: p.policyId,
        amount: BigInt(p.amount), paidAt: BigInt(p.paidAt), status: p.status,
      };
    },
    // The escrow never stores orderRef, but paymentId is indexed on Paid, so it is
    // recoverable from logs. This is what binds a payment to one session.
    //
    // Bounded lookback rather than fromBlock 0: public RPC providers cap eth_getLogs
    // ranges (drpc's free plan at 10k blocks), and an unbounded query fails outright
    // on any chain with real history. A payment being presented is necessarily
    // recent, so a window is both cheaper and sufficient.
    async getOrderRef(paymentId) {
      const head = await publicClient.getBlockNumber();
      const span = 9_000n;
      const logs = await publicClient.getContractEvents({
        address: escrow, abi: escrowAbi, eventName: "Paid", args: { paymentId },
        fromBlock: head > span ? head - span : 0n, toBlock: "latest",
      });
      return (logs[0]?.args.orderRef as Hex) ?? null;
    },
  };

  function quoteOptions(resourceUrl: string): QuoteOptions {
    return {
      resource: { url: resourceUrl, description: "Sentiment inference", mimeType: "application/json" },
      amount: BUDGET,
      asset: usdc,
      escrow,
      terms: {
        policyId: policyId.toString(),
        policyHash: policyHashValue,
        agreementHash: agreementHashValue,
        merchant: merchant.address,
        attestor: attestor.address,
        escrow,
        disputeWindow: DISPUTE_WINDOW,
        engineVersion: "1",
      },
    };
  }

  let policyHashValue: Hex;
  let agreementHashValue: Hex;

  beforeAll(async () => {
    log("\n=== setup ===");

    // Arc USDC is a Circle FiatToken and carries a blacklist. A blocked account
    // reverts with "Blocked address" inside whatever call touches it, which reads
    // as a contract bug rather than an account problem, so it is checked up front.
    if (LIVE) {
      const blacklistAbi = parseAbi(["function isBlacklisted(address) view returns (bool)"]);
      for (const [role, account] of [["merchant", merchant], ["buyer", buyer], ["attestor", attestor]] as const) {
        const blocked = await publicClient.readContract({
          address: EXISTING_USDC!, abi: blacklistAbi, functionName: "isBlacklisted", args: [account.address],
        });
        if (blocked) throw new Error(`${role} ${account.address} is blacklisted on this USDC and cannot transact`);
      }
      log("  preflight   no account is blacklisted");
    }
    usdc = EXISTING_USDC ?? (await deploy("TestUSDC", []));
    registry = EXISTING_REGISTRY ?? (await deploy("PolicyRegistry", []));
    // Adapter shares are tracked per holder, so a second escrow can share the one
    // already deployed without disturbing the payments the first one holds.
    const adapter = EXISTING_ADAPTER ?? (await deploy("MockUSYCAdapter", [usdc]));
    escrow = EXISTING_ESCROW ??
      (await deploy("RecourseEscrow", [usdc, registry, adapter, attestor.address, merchant.address, 1000, 60]));

    const policy = agentServicePolicy({ merchant: merchant.address, disputeWindowSeconds: DISPUTE_WINDOW });
    if (EXISTING_POLICY !== undefined) {
      policyId = EXISTING_POLICY;
    } else {
    let hash = await wallet(merchant).writeContract({
      address: registry, abi: registryAbi, functionName: "registerPolicy",
      args: [policy.disputeWindow, policy.defaultRefundBps, policy.rules, "ipfs://agent-service"],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    // Read rather than assume: the shared registry on Arc already holds policies.
    policyId = await publicClient.readContract({
      address: registry, abi: registryAbi, functionName: "policyCount",
    });

    // I8: the merchant names a third party, and cannot name itself.
    hash = await wallet(merchant).writeContract({
      address: escrow, abi: escrowAbi, functionName: "setPolicyAttestor", args: [policyId, attestor.address],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    }

    policyHashValue = await publicClient.readContract({
      address: registry, abi: registryAbi, functionName: "policyHash", args: [policyId],
    });
    agreementHashValue = await publicClient.readContract({
      address: escrow, abi: escrowAbi, functionName: "agreementHash", args: [policyId],
    });

    // Only the mock token can be minted. On a live chain the accounts are funded
    // already and the shared adapter carries its own yield buffer.
    if (!EXISTING_USDC) {
      for (const who of [buyer.address, adapter]) {
        const h = await wallet(merchant).writeContract({
          address: usdc, abi: usdcAbi, functionName: "mint", args: [who, 1_000_000_000n],
        });
        await publicClient.waitForTransactionReceipt({ hash: h });
      }
    }
    const approve = await wallet(buyer).writeContract({
      address: usdc, abi: usdcAbi, functionName: "approve", args: [escrow, 2n ** 255n],
    });
    await publicClient.waitForTransactionReceipt({ hash: approve });

    log(`  chain       ${CHAIN_ID}${LIVE ? " (live)" : " (anvil)"}`);
    log(`  escrow      ${escrow}`);
    log(`  registry    ${registry}${EXISTING_REGISTRY ? " (existing)" : ""}`);
    log(`  adapter     ${adapter}${EXISTING_ADAPTER ? " (existing)" : ""}`);
    log(`  policy      ${policyId}, ladder of 8 rules, default 5000 bps`);
    log(`  attestor    ${attestor.address} (not the merchant, enforced on chain)`);

    // The selling agent. Answers 402 with its refund terms, verifies before serving.
    server = createServer(async (req, res) => {
      const presented = req.headers[PAYMENT_SIGNATURE_HEADER.toLowerCase()] as string | undefined;
      const options = quoteOptions(`${origin}${req.url}`);

      if (!presented) {
        res.writeHead(402, { [PAYMENT_REQUIRED_HEADER]: quoteHeader(options), "content-type": "application/json" });
        res.end(JSON.stringify({ error: "payment required" }));
        return;
      }

      const result = await verify(presented, quote(options), reader);
      if (result.ok !== true) {
        res.writeHead(402, { "content-type": "application/json" });
        res.end(JSON.stringify(result));
        return;
      }

      // The service itself. Fails a controlled fraction so the demo can show both
      // outcomes without pretending either is special.
      served++;
      if (served % succeedEvery !== 0) {
        res.writeHead(503, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: "model overloaded" }));
        return;
      }
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ sentiment: "positive", score: 0.91 }));
    });

    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const address = server.address();
    origin = `http://127.0.0.1:${typeof address === "object" && address ? address.port : 0}`;
    log(`  seller      ${origin}`);

    evidenceServer = createServer((req, res) => {
      const body = publishedSessions.get((req.url ?? "").replace("/session/", ""));
      res.writeHead(body ? 200 : 404, { "content-type": "application/json" });
      res.end(JSON.stringify(body ?? { error: "not published" }));
    });
    await new Promise<void>((resolve) => evidenceServer.listen(0, "127.0.0.1", resolve));
    const evidenceAddress = evidenceServer.address();
    evidenceOrigin = `http://127.0.0.1:${typeof evidenceAddress === "object" && evidenceAddress ? evidenceAddress.port : 0}`;
    log(`  evidence    ${evidenceOrigin}`);
  }, 600_000);

  afterAll(() => {
    server?.close();
    evidenceServer?.close();
  });

  // The buyer's side of A5 steps 1 to 8, shared by both scenarios.
  async function runSession(sessionId: Hex, calls: number) {
    const first = await fetch(`${origin}/infer`);
    expect(first.status).toBe(402);

    const q = parseQuote(first.headers.get(PAYMENT_REQUIRED_HEADER)!);
    const check = await verifyTerms(q.terms!, {
      agreementHash: async () =>
        publicClient.readContract({ address: escrow, abi: escrowAbi, functionName: "agreementHash", args: [policyId] }),
      getPolicy: async () =>
        publicClient.readContract({ address: registry, abi: registryAbi, functionName: "getPolicy", args: [policyId] }) as never,
    });
    expect(check.ok).toBe(true);
    log(`  terms check ok. worst case ${check.assessment!.worstCaseRefundBps} bps, window ${check.assessment!.disputeWindow}s`);

    const hash = await wallet(buyer).writeContract({
      address: escrow, abi: escrowAbi, functionName: "pay", args: [policyId, BUDGET, sessionId],
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    const paid = await publicClient.getContractEvents({
      address: escrow, abi: escrowAbi, eventName: "Paid", blockHash: receipt.blockHash,
    });
    const paymentId = paid[0]!.args.paymentId!;
    log(`  escrowed    ${usd(BUDGET)} as payment ${paymentId}`);

    const header = buildPaymentHeader(q, { mode: "settled", paymentId: paymentId.toString(), sessionId });
    const recorder = new SessionRecorder(sessionId);

    for (let i = 0; i < calls; i++) {
      const started = Date.now();
      const response = await fetch(`${origin}/infer`, { headers: { [PAYMENT_SIGNATURE_HEADER]: header } });
      const body = await response.text();
      recorder.record({
        requestHash: keccak256(new TextEncoder().encode(`${sessionId}:${i}`)),
        responseHash: keccak256(new TextEncoder().encode(body)),
        statusCode: response.status,
        latencyMs: Math.max(1, Date.now() - started),
        schemaValid: response.status === 200,
      });
    }

    return { paymentId, recorder };
  }

  // No cheating on a live chain: the window is waited out rather than warped past.
  async function advancePast(seconds: number) {
    if (!LIVE) {
      await publicClient.request({ method: "evm_increaseTime" as never, params: [seconds] as never });
      await publicClient.request({ method: "evm_mine" as never, params: [] as never });
      return;
    }
    log(`  waiting     ${seconds}s for the dispute window to close`);
    await new Promise((r) => setTimeout(r, seconds * 1000));
  }

  it("pays for a service that works, and the service keeps the money", async () => {
    log("\n=== scenario A: the service delivers ===");
    succeedEvery = 1;
    served = 0;
    const merchantBefore = await publicClient.readContract({
      address: usdc, abi: usdcAbi, functionName: "balanceOf", args: [merchant.address],
    });

    const { paymentId, recorder } = await runSession(`0x${"a1".repeat(32)}`, 5);
    log(`  session     ${recorder.length} calls, ${recorder.failed} failed`);
    expect(recorder.failed).toBe(0);
    expect(severity(recorder.failed, recorder.length)).toBe(SlaOutcome.Clean);

    // The buyer does nothing. Doing nothing is what paying looks like.
    await advancePast(DISPUTE_WINDOW + 15);

    const hash = await wallet(buyer).writeContract({
      address: escrow, abi: escrowAbi, functionName: "release", args: [paymentId],
    });
    await publicClient.waitForTransactionReceipt({ hash });

    const merchantAfter = await publicClient.readContract({
      address: usdc, abi: usdcAbi, functionName: "balanceOf", args: [merchant.address],
    });
    log(`  released    merchant +${usd(merchantAfter - merchantBefore)}`);
    expect(merchantAfter - merchantBefore).toBeGreaterThanOrEqual(BUDGET);
  }, 600_000);

  it("refunds a session the service mostly failed, with no human involved", async () => {
    log("\n=== scenario B: the service breaks its SLA ===");
    // Succeeds on every 4th call: 5 of 20 succeed, 15 fail, exactly the 0.75 ratio
    // that the published ladder calls SEVERE.
    succeedEvery = 4;
    served = 0;
    const buyerBefore = await publicClient.readContract({
      address: usdc, abi: usdcAbi, functionName: "balanceOf", args: [buyer.address],
    });

    const sessionId = `0x${"b2".repeat(32)}` as Hex;
    const { paymentId, recorder } = await runSession(sessionId, 20);

    const bucket = severity(recorder.failed, recorder.length);
    log(`  session     ${recorder.length} calls, ${recorder.failed} failed -> severity ${bucket}`);
    expect(recorder.failed).toBeGreaterThan(10);
    expect(bucket).toBe(SlaOutcome.Severe);

    // The buyer files what the log proves, and nothing more.
    const draft = recorder.draft();
    expect(draft.claimType).toBe(AgentClaimType.PartialFailure);
    expect(draft.items[0]!.evType).toBe(AgentEvidence.CallLogRoot);

    let hash = await wallet(buyer).writeContract({
      address: escrow, abi: escrowAbi, functionName: "fileDispute",
      args: [paymentId, draft.claimType, draft.items.map((i) => ({ evType: i.evType, hash: i.hash }))],
    });
    await publicClient.waitForTransactionReceipt({ hash });

    // The buyer publishes its log so the dispute can be checked by anyone.
    publishedSessions.set(sessionId, recorder.publish());

    // From here the attestor has only two things: the URL, and the root already on
    // chain. It never touches `recorder`. Everything it signs it derived itself.
    const onchain = await publicClient.readContract({
      address: escrow, abi: escrowAbi, functionName: "getPayment", args: [paymentId],
    });
    expect(onchain.evidenceRoot).toBe(draft.evidenceRoot);

    const fetched = await (await fetch(`${evidenceOrigin}/session/${sessionId}`)).json();
    const review = reviewSession(fetched, onchain.evidenceRoot);
    expect(review.attestable).toBe(true);
    if (!review.attestable) throw new Error(review.reason);

    // A doctored log must not be attestable against the same on chain root. The
    // edit here is a latency value, which changes no verdict at all: the log is
    // pinned exactly, not approximately, so even a cosmetic edit is refused.
    const tampered = JSON.parse(JSON.stringify(fetched));
    tampered.calls[0].latencyMs = fetched.calls[0].latencyMs + 1;
    expect(reviewSession(tampered, onchain.evidenceRoot).attestable).toBe(false);

    const independent = review.attValue;
    expect(independent).toBe(severity(recorder.failed, recorder.length));
    log(`  attestor    fetched log, root matches chain, derives ${review.failed}/${review.total} -> severity ${independent}`);
    log(`              a tampered copy of the same log is refused`);

    // Signed and submitted by the daemon rather than inline, so what runs here is
    // the same code path a standalone attestor process takes: read the dispute off
    // chain, fetch the published log, review it, sign, submit.
    const attestorChain: AttestorChain = {
      recentDisputes: async () => [paymentId],
      async getPayment(id) {
        const p = await publicClient.readContract({
          address: escrow, abi: escrowAbi, functionName: "getPayment", args: [id],
        });
        return p.status === 0 ? null : {
          paymentId: id, policyId: p.policyId, evidenceRoot: p.evidenceRoot,
          claimType: p.claimType, attType: p.attType, status: p.status,
        };
      },
      orderRef: async (id) => (await reader.getOrderRef(id)) as Hex,
      attestorFor: (id) =>
        publicClient.readContract({ address: escrow, abi: escrowAbi, functionName: "attestorFor", args: [id] }),
      attestationDigest: (id, attType, value, deadline) =>
        publicClient.readContract({
          address: escrow, abi: escrowAbi, functionName: "attestationDigest",
          args: [id, attType, value, deadline],
        }),
      async submitAttestation(id, attType, value, deadline, signature) {
        const h = await wallet(attestor).writeContract({
          address: escrow, abi: escrowAbi, functionName: "submitAttestation",
          args: [id, attType, value, deadline, signature],
        });
        await publicClient.waitForTransactionReceipt({ hash: h });
        return h;
      },
    };

    const attestorDeps: AttestorDeps = {
      chain: attestorChain,
      fetchSession: async (id) => (await fetch(`${evidenceOrigin}/session/${id}`)).json(),
      sign: (digest) => attestor.sign({ hash: digest }),
      self: attestor.address,
      // Chain time. Scenario A warped this node forward, so the wall clock is
      // behind block.timestamp and a deadline derived from it is already expired.
      nowSeconds: async () => Number((await publicClient.getBlock()).timestamp),
    };

    const sweep = await sweepOnce(attestorDeps);
    expect(sweep.skipped).toEqual([]);
    expect(sweep.attested).toHaveLength(1);
    expect(sweep.attested[0]!.attValue).toBe(independent);
    log(`  daemon      swept 1 dispute and submitted the attestation`);

    // Running again must change nothing: an attestation is one-shot on chain.
    const again = await sweepOnce(attestorDeps);
    expect(again.attested).toEqual([]);
    expect(again.skipped[0]!.reason).toBe("already attested");
    log(`              a second sweep correctly does nothing`);

    // Permissionless: the buyer settles its own dispute because anyone can.
    hash = await wallet(buyer).writeContract({
      address: escrow, abi: escrowAbi, functionName: "resolve", args: [paymentId],
    });
    await publicClient.waitForTransactionReceipt({ hash });

    const settled = await publicClient.readContract({
      address: escrow, abi: escrowAbi, functionName: "getPayment", args: [paymentId],
    });
    const buyerAfter = await publicClient.readContract({
      address: usdc, abi: usdcAbi, functionName: "balanceOf", args: [buyer.address],
    });
    const net = buyerAfter - buyerBefore;

    const principal = -(BUDGET / 2n);
    log(`  resolved    verdict ${settled.verdictBps} bps, buyer net ${usd(net)} on a ${usd(BUDGET)} budget`);
    if (LIVE) log(`              of which ${usd(principal - net)} is gas, because gas on Arc is USDC`);
    log(`  no human was involved at any point\n`);

    expect(settled.status).toBe(EscrowStatus.Settled);
    expect(settled.verdictBps).toBe(5000); // SEVERE rung of the published ladder

    if (!LIVE) {
      expect(net).toBe(principal);
    } else {
      // On Arc the gas token is USDC itself, so the buyer's balance also carries
      // what it spent on pay, fileDispute and resolve. The refund is exact; the
      // wallet delta cannot be, so it is bounded rather than pinned.
      expect(net).toBeLessThanOrEqual(principal);
      expect(net).toBeGreaterThan(principal - 50_000n); // 0.05 USDC of gas headroom
    }
  }, 600_000);
});
