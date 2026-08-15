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

// anvil's first three deterministic accounts.
const KEYS = {
  merchant: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  buyer: "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  attestor: "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
} as const;

const here = dirname(fileURLToPath(import.meta.url));
const artifact = (name: string) =>
  JSON.parse(readFileSync(join(here, `../../contracts/out/${name}.sol/${name}.json`), "utf8"));

const anvil = defineChain({
  id: 31337,
  name: "Anvil",
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
  "function registerPolicy(uint32 disputeWindow, uint16 defaultRefundBps, (uint8 claimType, uint16 requiredEvidenceMask, uint8 attType, uint8 attExpected, uint32 claimWindow, uint16 refundBps, bool requiresReturn)[] rules, string metadataURI) returns (uint256)",
  "function policyHash(uint256 policyId) view returns (bytes32)",
  "function getPolicy(uint256 policyId) view returns ((address merchant, uint32 disputeWindow, uint16 defaultRefundBps, (uint8 claimType, uint16 requiredEvidenceMask, uint8 attType, uint8 attExpected, uint32 claimWindow, uint16 refundBps, bool requiresReturn)[] rules))",
]);
const usdcAbi = parseAbi([
  "function mint(address to, uint256 amount)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function balanceOf(address a) view returns (uint256)",
]);

const DISPUTE_WINDOW = 3600;
const BUDGET = 5_000_000n; // 5 USDC session budget
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
    async getOrderRef(paymentId) {
      const logs = await publicClient.getContractEvents({
        address: escrow, abi: escrowAbi, eventName: "Paid",
        args: { paymentId }, fromBlock: 0n, toBlock: "latest",
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
    usdc = await deploy("TestUSDC", []);
    registry = await deploy("PolicyRegistry", []);
    const adapter = await deploy("MockUSYCAdapter", [usdc]);
    escrow = await deploy("RecourseEscrow", [usdc, registry, adapter, attestor.address, merchant.address, 1000, 60]);

    const policy = agentServicePolicy({ merchant: merchant.address, disputeWindowSeconds: DISPUTE_WINDOW });
    let hash = await wallet(merchant).writeContract({
      address: registry, abi: registryAbi, functionName: "registerPolicy",
      args: [policy.disputeWindow, policy.defaultRefundBps, policy.rules, "ipfs://agent-service"],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    policyId = 1n;

    // I8: the merchant names a third party, and cannot name itself.
    hash = await wallet(merchant).writeContract({
      address: escrow, abi: escrowAbi, functionName: "setPolicyAttestor", args: [policyId, attestor.address],
    });
    await publicClient.waitForTransactionReceipt({ hash });

    policyHashValue = await publicClient.readContract({
      address: registry, abi: registryAbi, functionName: "policyHash", args: [policyId],
    });
    agreementHashValue = await publicClient.readContract({
      address: escrow, abi: escrowAbi, functionName: "agreementHash", args: [policyId],
    });

    for (const who of [buyer.address, adapter]) {
      const h = await wallet(merchant).writeContract({
        address: usdc, abi: usdcAbi, functionName: "mint", args: [who, 1_000_000_000n],
      });
      await publicClient.waitForTransactionReceipt({ hash: h });
    }
    const approve = await wallet(buyer).writeContract({
      address: usdc, abi: usdcAbi, functionName: "approve", args: [escrow, 2n ** 255n],
    });
    await publicClient.waitForTransactionReceipt({ hash: approve });

    log(`  escrow      ${escrow}`);
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
  }, 120_000);

  afterAll(() => {
    server?.close();
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
    await publicClient.request({ method: "evm_increaseTime" as never, params: [DISPUTE_WINDOW + 60] as never });
    await publicClient.request({ method: "evm_mine" as never, params: [] as never });

    const hash = await wallet(buyer).writeContract({
      address: escrow, abi: escrowAbi, functionName: "release", args: [paymentId],
    });
    await publicClient.waitForTransactionReceipt({ hash });

    const merchantAfter = await publicClient.readContract({
      address: usdc, abi: usdcAbi, functionName: "balanceOf", args: [merchant.address],
    });
    log(`  released    merchant +${usd(merchantAfter - merchantBefore)}`);
    expect(merchantAfter - merchantBefore).toBeGreaterThanOrEqual(BUDGET);
  }, 120_000);

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

    // The attestor recomputes the root from the published log and signs the bucket
    // it derives itself. It never decides the refund; the policy already did.
    const onchain = await publicClient.readContract({
      address: escrow, abi: escrowAbi, functionName: "getPayment", args: [paymentId],
    });
    expect(onchain.evidenceRoot).toBe(draft.evidenceRoot);
    const independent = severity(recorder.failed, recorder.length);
    log(`  attestor    recomputed root matches, signs severity ${independent}`);

    const deadline = BigInt(Math.floor(Date.now() / 1000) + 86_400);
    const digest = await publicClient.readContract({
      address: escrow, abi: escrowAbi, functionName: "attestationDigest",
      args: [paymentId, ATT_SLA_OUTCOME, independent, deadline],
    });
    const signature = await attestor.sign({ hash: digest });

    hash = await wallet(attestor).writeContract({
      address: escrow, abi: escrowAbi, functionName: "submitAttestation",
      args: [paymentId, ATT_SLA_OUTCOME, independent, deadline, signature],
    });
    await publicClient.waitForTransactionReceipt({ hash });

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

    log(`  resolved    verdict ${settled.verdictBps} bps, buyer net ${usd(net)} on a ${usd(BUDGET)} budget`);
    log(`  no human was involved at any point\n`);

    expect(settled.status).toBe(EscrowStatus.Settled);
    expect(settled.verdictBps).toBe(5000); // SEVERE rung of the published ladder
    expect(net).toBe(-(BUDGET / 2n));
  }, 120_000);
});
