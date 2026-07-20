import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { compute } from "../src/engine";
import { policyHash, verdictHash } from "../src/hash";
import type { Policy, Rule, VerdictInput } from "../src/types";

const here = dirname(fileURLToPath(import.meta.url));
const vectorsDir = join(here, "../../packages/vectors");

const vectors = JSON.parse(readFileSync(join(vectorsDir, "verdicts.json"), "utf8")) as Record<string, RawCase>;
const hashes = JSON.parse(readFileSync(join(vectorsDir, "hashes.json"), "utf8")) as Record<string, RawHashes>;

interface RawHashes {
  policyHash: `0x${string}`;
  verdictHash: `0x${string}`;
}

interface RawCase {
  paymentId: number;
  policy: {
    merchant: `0x${string}`;
    disputeWindow: number;
    defaultRefundBps: number;
    rules: {
      claimType: number[];
      requiredEvidenceMask: number[];
      attType: number[];
      attExpected: number[];
      claimWindow: number[];
      refundBps: number[];
      requiresReturn: boolean[];
    };
  };
  input: { claimType: number; evidenceMask: number; attType: number; attValue: number; paidAt: number; filedAt: number };
  expect: { refundBps: number; requiresReturn: boolean; ruleIndex: number; matched: boolean };
}

// Rebuild the struct-of-arrays rules into the Rule[] the engine consumes.
function toPolicy(raw: RawCase["policy"]): Policy {
  const r = raw.rules;
  const rules: Rule[] = r.claimType.map((_, k) => ({
    claimType: r.claimType[k]!,
    requiredEvidenceMask: r.requiredEvidenceMask[k]!,
    attType: r.attType[k]!,
    attExpected: r.attExpected[k]!,
    claimWindow: r.claimWindow[k]!,
    refundBps: r.refundBps[k]!,
    requiresReturn: r.requiresReturn[k]!,
  }));
  return { merchant: raw.merchant, disputeWindow: raw.disputeWindow, defaultRefundBps: raw.defaultRefundBps, rules };
}

function toInput(raw: RawCase["input"]): VerdictInput {
  return {
    claimType: raw.claimType,
    evidenceMask: raw.evidenceMask,
    attType: raw.attType,
    attValue: raw.attValue,
    paidAt: BigInt(raw.paidAt),
    filedAt: BigInt(raw.filedAt),
  };
}

describe("golden vectors: TS engine parity with Solidity", () => {
  const names = Object.keys(vectors);

  it("loads the shared vector files", () => {
    expect(names.length).toBeGreaterThan(0);
    expect(Object.keys(hashes).sort()).toEqual([...names].sort());
  });

  for (const name of names) {
    it(name, () => {
      const c = vectors[name]!;
      const p = toPolicy(c.policy);
      const input = toInput(c.input);

      const v = compute(p, input);
      expect(v.refundBps).toBe(c.expect.refundBps);
      expect(v.requiresReturn).toBe(c.expect.requiresReturn);
      expect(v.ruleIndex).toBe(c.expect.ruleIndex);
      expect(v.matched).toBe(c.expect.matched);

      const ph = policyHash(p);
      const vh = verdictHash(ph, BigInt(c.paymentId), input, v);
      expect(ph).toBe(hashes[name]!.policyHash);
      expect(vh).toBe(hashes[name]!.verdictHash);
    });
  }
});
