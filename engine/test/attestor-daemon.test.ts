import { describe, it, expect } from "vitest";
import { sweepOnce, runDaemon } from "../src/attestor-daemon";
import type { AttestorChain, AttestorDeps, DisputedPayment } from "../src/attestor-daemon";
import { SessionRecorder } from "../src/session";
import type { CallRecord } from "../src/session";
import { SlaOutcome } from "../src/types";

const SELF = "0x00000000000000000000000000000000000000A3" as const;
const OTHER = "0x00000000000000000000000000000000000000C9" as const;
const SESSION = `0x${"d4".repeat(32)}` as const;

const call = (i: number, over: Partial<CallRecord> = {}): CallRecord => ({
  requestHash: `0x${(0xa0000000 + i).toString(16).padStart(64, "0")}`,
  responseHash: `0x${(0xb0000000 + i).toString(16).padStart(64, "0")}`,
  statusCode: 200,
  latencyMs: 120,
  schemaValid: true,
  ...over,
});

// 15 of 20 failed: the exact 0.75 ratio the ladder calls SEVERE.
function severeSession() {
  const recorder = new SessionRecorder(SESSION);
  for (let i = 0; i < 20; i++) {
    recorder.record(i % 4 === 3 ? call(i) : call(i, { statusCode: 503, schemaValid: false }));
  }
  return { published: JSON.parse(JSON.stringify(recorder.publish())), filed: recorder.draft().evidenceRoot };
}

function harness(over: {
  payment?: Partial<DisputedPayment>;
  attestor?: `0x${string}`;
  orderRef?: `0x${string}` | null;
  fetchSession?: AttestorDeps["fetchSession"];
  disputes?: bigint[];
} = {}) {
  const { published, filed } = severeSession();
  const submitted: { paymentId: bigint; value: number }[] = [];
  const lines: string[] = [];

  const payment: DisputedPayment = {
    paymentId: 7n, policyId: 9n, evidenceRoot: filed, claimType: 8, attType: 0, status: 2, ...over.payment,
  };

  const chain: AttestorChain = {
    recentDisputes: async () => over.disputes ?? [7n],
    getPayment: async (id) => (id === payment.paymentId ? payment : null),
    orderRef: async () => (over.orderRef === undefined ? SESSION : over.orderRef),
    attestorFor: async () => over.attestor ?? SELF,
    attestationDigest: async () => `0x${"11".repeat(32)}`,
    submitAttestation: async (paymentId, _t, value) => {
      submitted.push({ paymentId, value });
      // The chain enforces one attestation per payment; mirror that here so a
      // second sweep in the same test sees the world it would really see.
      payment.attType = 2;
      return `0x${"ab".repeat(32)}`;
    },
  };

  const deps: AttestorDeps = {
    chain,
    fetchSession: over.fetchSession ?? (async () => published),
    sign: async () => `0x${"cd".repeat(65)}`,
    self: SELF,
    nowSeconds: () => 1_700_000_000,
    log: (l) => lines.push(l),
  };

  return { deps, submitted, lines, published, filed, payment };
}

describe("attestor daemon", () => {
  it("attests a verifiable dispute", async () => {
    const { deps, submitted } = harness();
    const summary = await sweepOnce(deps);

    expect(summary.seen).toBe(1);
    expect(summary.skipped).toEqual([]);
    expect(summary.attested).toHaveLength(1);
    expect(summary.attested[0]!.attValue).toBe(SlaOutcome.Severe);
    expect(submitted).toEqual([{ paymentId: 7n, value: SlaOutcome.Severe }]);
  });

  // An attestation is one-shot on chain, so a second sweep must not resubmit.
  it("is idempotent across sweeps", async () => {
    const { deps, submitted } = harness();
    await sweepOnce(deps);
    const second = await sweepOnce(deps);

    expect(submitted).toHaveLength(1);
    expect(second.attested).toEqual([]);
    expect(second.skipped[0]!.reason).toBe("already attested");
  });

  it("does not act for a policy that named someone else", async () => {
    const { deps, submitted } = harness({ attestor: OTHER });
    const summary = await sweepOnce(deps);

    expect(submitted).toEqual([]);
    expect(summary.skipped[0]!.reason).toContain("names a different attestor");
  });

  it("ignores payments that are not disputed", async () => {
    for (const status of [1, 3]) {
      const { deps, submitted } = harness({ payment: { status } });
      const summary = await sweepOnce(deps);
      expect(submitted).toEqual([]);
      expect(summary.skipped[0]!.reason).toContain("not disputed");
    }
  });

  // Staying silent is the correct outcome, not a failure: the dispute then resolves
  // to the policy default rather than to a number nobody could check.
  it("stays silent when the buyer never published", async () => {
    const { deps, submitted } = harness({
      fetchSession: async () => { throw new Error("404"); },
    });
    const summary = await sweepOnce(deps);

    expect(submitted).toEqual([]);
    expect(summary.skipped[0]!.reason).toContain("published session unavailable");
  });

  it("refuses a published log that does not match what was filed", async () => {
    const { published } = severeSession();
    const doctored = JSON.parse(JSON.stringify(published));
    doctored.calls[0].latencyMs += 1;

    const { deps, submitted } = harness({ fetchSession: async () => doctored });
    const summary = await sweepOnce(deps);

    expect(submitted).toEqual([]);
    expect(summary.skipped[0]!.reason).toContain("refusing to attest");
  });

  it("skips a payment whose session cannot be recovered", async () => {
    const { deps, submitted } = harness({ orderRef: null });
    const summary = await sweepOnce(deps);
    expect(submitted).toEqual([]);
    expect(summary.skipped[0]!.reason).toContain("could not recover the session");
  });

  // One bad dispute must not stop the others being attested.
  it("keeps going when a single dispute throws", async () => {
    const { deps, submitted } = harness({ disputes: [99n, 7n] });
    const summary = await sweepOnce(deps);

    expect(summary.seen).toBe(2);
    expect(summary.skipped[0]!.reason).toBe("no such payment");
    expect(submitted).toEqual([{ paymentId: 7n, value: SlaOutcome.Severe }]);
  });

  it("survives the dispute query itself failing", async () => {
    const { deps } = harness();
    deps.chain.recentDisputes = async () => { throw new Error("rpc down"); };
    const summary = await sweepOnce(deps);
    expect(summary).toMatchObject({ seen: 0, attested: [], skipped: [] });
  });

  it("signs with a deadline in the future", async () => {
    const { deps } = harness();
    let seen = 0n;
    deps.chain.attestationDigest = async (_p, _t, _v, deadline) => {
      seen = deadline;
      return `0x${"11".repeat(32)}`;
    };
    await sweepOnce(deps, { deadlineSeconds: 600 });
    expect(seen).toBe(BigInt((await deps.nowSeconds()) + 600));
  });

  it("loops until aborted", async () => {
    const { deps, submitted } = harness();
    const controller = new AbortController();
    const done = runDaemon(deps, { intervalMs: 1, signal: controller.signal });
    await new Promise((r) => setTimeout(r, 20));
    controller.abort();
    await done;
    // Attested once on the first pass, then correctly idle.
    expect(submitted).toHaveLength(1);
  });
});
