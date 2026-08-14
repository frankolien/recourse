import { describe, it, expect } from "vitest";
import { severity, agentServicePolicy, AgentPolicyError, DEFAULT_SLA_LADDER } from "../src/agent";
import { compute } from "../src/engine";
import { AgentClaimType, AgentEvidence, ATT_SLA_OUTCOME, SlaOutcome, NO_RULE } from "../src/types";
import type { VerdictInput } from "../src/types";

const MERCHANT = "0x00000000000000000000000000000000000000A2" as const;
const WINDOW = 3600;
const PAID = 1_700_000_000n;

const policy = agentServicePolicy({ merchant: MERCHANT, disputeWindowSeconds: WINDOW });

function input(over: Partial<VerdictInput>): VerdictInput {
  return {
    claimType: AgentClaimType.PartialFailure,
    evidenceMask: AgentEvidence.CallLogRoot,
    attType: ATT_SLA_OUTCOME,
    attValue: SlaOutcome.Clean,
    paidAt: PAID,
    filedAt: PAID + 600n,
    ...over,
  };
}

describe("severity bucketing", () => {
  it("returns Clean only for a session with no failures", () => {
    expect(severity(0, 20)).toBe(SlaOutcome.Clean);
    expect(severity(0, 1)).toBe(SlaOutcome.Clean);
  });

  // The boundaries are the whole point: these are the ratios where binary
  // floating point would be a coin flip, so they are pinned explicitly.
  it("puts each boundary ratio in the lower severity", () => {
    expect(severity(1, 20)).toBe(SlaOutcome.Minor); // exactly 0.05
    expect(severity(5, 20)).toBe(SlaOutcome.Moderate); // exactly 0.25
    expect(severity(15, 20)).toBe(SlaOutcome.Severe); // exactly 0.75
  });

  it("steps up one bucket past each boundary", () => {
    expect(severity(2, 20)).toBe(SlaOutcome.Moderate);
    expect(severity(6, 20)).toBe(SlaOutcome.Severe);
    expect(severity(16, 20)).toBe(SlaOutcome.Total);
    expect(severity(20, 20)).toBe(SlaOutcome.Total);
  });

  it("agrees at large session sizes where a float would drift", () => {
    expect(severity(50_000, 1_000_000)).toBe(SlaOutcome.Minor); // exactly 0.05
    expect(severity(50_001, 1_000_000)).toBe(SlaOutcome.Moderate);
  });

  it("rejects inputs that are not a failure rate", () => {
    expect(() => severity(0, 0)).toThrow(AgentPolicyError);
    expect(() => severity(3, 2)).toThrow(AgentPolicyError);
    expect(() => severity(-1, 10)).toThrow(AgentPolicyError);
    expect(() => severity(1.5, 10)).toThrow(AgentPolicyError);
  });
});

describe("agent service policy", () => {
  it("declares the ladder before the broader claims", () => {
    expect(policy.rules).toHaveLength(8);
    expect(policy.rules.slice(0, 5).map((r) => r.attExpected)).toEqual([0, 1, 2, 3, 4]);
    expect(policy.rules.slice(0, 5).every((r) => r.claimType === AgentClaimType.PartialFailure)).toBe(true);
    expect(policy.rules.slice(0, 5).map((r) => r.refundBps)).toEqual([0, 1_000, 2_500, 5_000, 10_000]);
  });

  it("leaves room for further rules under the engine cap", () => {
    expect(policy.rules.length).toBeLessThan(16);
  });

  it("defaults to the neutral split when the attestor says nothing", () => {
    expect(policy.defaultRefundBps).toBe(5_000);
  });

  it("rejects a malformed merchant and an out-of-range ladder", () => {
    expect(() => agentServicePolicy({ merchant: "0xnope" as never, disputeWindowSeconds: WINDOW })).toThrow(AgentPolicyError);
    expect(() =>
      agentServicePolicy({
        merchant: MERCHANT,
        disputeWindowSeconds: WINDOW,
        ladder: { ...DEFAULT_SLA_LADDER, [SlaOutcome.Total]: 10_001 },
      }),
    ).toThrow(AgentPolicyError);
  });
});

// The authored policy must produce the outcomes pinned in packages/vectors, so a
// change to agent.ts that drifts from the golden file fails here rather than in
// production.
describe("authored policy reproduces the golden outcomes", () => {
  it("selects the ladder rung matching the attested severity", () => {
    for (const [attValue, expected] of [[0, 0], [1, 1_000], [2, 2_500], [3, 5_000], [4, 10_000]] as const) {
      const v = compute(policy, input({ attValue }));
      expect(v).toMatchObject({ refundBps: expected, ruleIndex: attValue, matched: true });
    }
  });

  it("falls to the default when no attestation arrived", () => {
    const v = compute(policy, input({ attType: 0, attValue: 0 }));
    expect(v).toMatchObject({ refundBps: 5_000, ruleIndex: NO_RULE, matched: false });
  });

  it("settles the mechanical claims without an attestor", () => {
    const notServed = compute(
      policy,
      input({ claimType: AgentClaimType.NotServed, evidenceMask: AgentEvidence.Unreachable, attType: 0 }),
    );
    expect(notServed).toMatchObject({ refundBps: 10_000, ruleIndex: 5, matched: true });

    const schema = compute(
      policy,
      input({
        claimType: AgentClaimType.SchemaViolation,
        evidenceMask: AgentEvidence.CallLogRoot | AgentEvidence.SchemaFailure,
        attType: 0,
      }),
    );
    expect(schema).toMatchObject({ refundBps: 10_000, ruleIndex: 6, matched: true });
  });

  it("denies a schema claim that anchors no failing response", () => {
    const v = compute(
      policy,
      input({ claimType: AgentClaimType.SchemaViolation, evidenceMask: AgentEvidence.CallLogRoot, attType: 0 }),
    );
    expect(v).toMatchObject({ refundBps: 5_000, ruleIndex: NO_RULE, matched: false });
  });

  it("includes the claim window boundary and excludes one second past it", () => {
    const at = compute(policy, input({ attValue: SlaOutcome.Total, filedAt: PAID + BigInt(WINDOW) }));
    expect(at).toMatchObject({ refundBps: 10_000, ruleIndex: 4, matched: true });

    const past = compute(policy, input({ attValue: SlaOutcome.Total, filedAt: PAID + BigInt(WINDOW) + 1n }));
    expect(past).toMatchObject({ refundBps: 5_000, ruleIndex: NO_RULE, matched: false });
  });
});
