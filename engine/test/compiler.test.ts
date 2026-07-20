import { describe, it, expect } from "vitest";
import { compilePolicy, toSpec, PolicyCompileError, type PolicySpec } from "../src/compiler";
import { compute } from "../src/engine";
import { policyHash } from "../src/hash";
import type { Policy } from "../src/types";

const MERCHANT = "0xD70beb0ce6E261fdaa8Cb72607316C6bcA16A082" as const;
const DAY = 86_400;

// The exact rules the seed script registers as policy #1. Compiling the authored
// spec below must reproduce these structs (and therefore the same policyHash the
// PolicyRegistry stored on Arc), proving the compiler agrees with the chain.
const SEED_POLICY: Policy = {
  merchant: MERCHANT,
  disputeWindow: 14 * DAY,
  defaultRefundBps: 0,
  rules: [
    { claimType: 0, requiredEvidenceMask: 0, attType: 1, attExpected: 2, claimWindow: 14 * DAY, refundBps: 10_000, requiresReturn: false },
    { claimType: 1, requiredEvidenceMask: 1, attType: 0, attExpected: 0, claimWindow: 3 * DAY, refundBps: 10_000, requiresReturn: true },
  ],
};

const SEED_SPEC: PolicySpec = {
  version: 1,
  disputeWindowSeconds: 14 * DAY,
  defaultRefundBps: 0,
  rules: [
    { id: "not-delivered-full", claimType: "NOT_DELIVERED", requiredEvidence: [], attestation: { type: "DELIVERY_STATUS", equals: "NOT_DELIVERED" }, claimWindowSeconds: 14 * DAY, refundBps: 10_000, requiresReturn: false },
    { id: "damaged-full", claimType: "DAMAGED", requiredEvidence: ["PHOTO"], attestation: null, claimWindowSeconds: 3 * DAY, refundBps: 10_000, requiresReturn: true },
  ],
};

describe("compilePolicy", () => {
  it("compiles the seed spec into the exact on-chain structs", () => {
    expect(compilePolicy(SEED_SPEC, MERCHANT)).toEqual(SEED_POLICY);
  });

  it("produces the same policyHash as the seeded structs", () => {
    expect(policyHash(compilePolicy(SEED_SPEC, MERCHANT))).toBe(policyHash(SEED_POLICY));
  });

  it("maps evidence names to the canonical bitmask", () => {
    const spec: PolicySpec = {
      disputeWindowSeconds: DAY,
      defaultRefundBps: 0,
      rules: [{ claimType: "NOT_AS_DESCRIBED", requiredEvidence: ["PHOTO", "DESCRIPTION", "VIDEO"], attestation: null, claimWindowSeconds: DAY, refundBps: 5_000, requiresReturn: false }],
    };
    expect(compilePolicy(spec, MERCHANT).rules[0]!.requiredEvidenceMask).toBe(1 | 2 | 8);
  });

  it("round-trips through toSpec back to the same hash", () => {
    const spec = toSpec(SEED_POLICY);
    expect(policyHash(compilePolicy(spec, MERCHANT))).toBe(policyHash(SEED_POLICY));
  });

  it("compiled rules drive compute the same as hand-built structs", () => {
    const policy = compilePolicy(SEED_SPEC, MERCHANT);
    const input = { claimType: 0, evidenceMask: 0, attType: 1, attValue: 2, paidAt: 1000n, filedAt: 2000n };
    expect(compute(policy, input)).toEqual({ refundBps: 10_000, requiresReturn: false, ruleIndex: 0, matched: true });
  });

  it("rejects too many rules", () => {
    const rule = SEED_SPEC.rules[0]!;
    const spec: PolicySpec = { disputeWindowSeconds: DAY, defaultRefundBps: 0, rules: Array.from({ length: 17 }, () => rule) };
    expect(() => compilePolicy(spec, MERCHANT)).toThrow(PolicyCompileError);
  });

  it("rejects a refund over 100 percent", () => {
    const spec: PolicySpec = {
      disputeWindowSeconds: DAY,
      defaultRefundBps: 0,
      rules: [{ claimType: "OTHER", requiredEvidence: [], attestation: null, claimWindowSeconds: DAY, refundBps: 10_001, requiresReturn: false }],
    };
    expect(() => compilePolicy(spec, MERCHANT)).toThrow(/refundBps/);
  });

  it("rejects an unknown claim type", () => {
    const spec = { disputeWindowSeconds: DAY, defaultRefundBps: 0, rules: [{ claimType: "REFUND_PLEASE", requiredEvidence: [], attestation: null, claimWindowSeconds: DAY, refundBps: 0, requiresReturn: false }] } as unknown as PolicySpec;
    expect(() => compilePolicy(spec, MERCHANT)).toThrow(PolicyCompileError);
  });

  it("rejects a bad merchant address", () => {
    expect(() => compilePolicy(SEED_SPEC, "0x1234" as `0x${string}`)).toThrow(/merchant/);
  });
});
