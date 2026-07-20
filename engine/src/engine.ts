import { type Policy, type VerdictInput, type Verdict, NO_RULE, MAX_RULES } from "./types";

// Mirror of PolicyEngine.compute in Solidity: first-match-wins, evidence bitmask
// subset check, attestation type-and-value match, inclusive
// [paidAt, paidAt + claimWindow] window, filed-before-paid guard. Any change here
// must land with the Solidity engine and a regenerated hashes.json in one commit.
export function compute(p: Policy, i: VerdictInput): Verdict {
  const n = Math.min(p.rules.length, MAX_RULES);

  for (let idx = 0; idx < n; idx++) {
    const r = p.rules[idx]!;

    if (r.claimType !== i.claimType) continue;

    if ((i.evidenceMask & r.requiredEvidenceMask) !== r.requiredEvidenceMask) continue;

    if (r.attType !== 0) {
      if (i.attType !== r.attType) continue;
      if (i.attValue !== r.attExpected) continue;
    }

    if (i.filedAt < i.paidAt) continue;
    if (i.filedAt > i.paidAt + BigInt(r.claimWindow)) continue;

    return { refundBps: r.refundBps, requiresReturn: r.requiresReturn, ruleIndex: idx, matched: true };
  }

  return { refundBps: p.defaultRefundBps, requiresReturn: false, ruleIndex: NO_RULE, matched: false };
}
