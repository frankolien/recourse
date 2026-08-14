// Agent commerce vocabulary and the standard service policy, docs/agent-settlement.md
// sections A1 to A3. This adds no verdict logic: matching stays in engine.ts (R2).
// Kept separate from compiler.ts because that module authors parcel policies from
// human-facing names, and these policies are authored by machines.

import { AgentClaimType, AgentEvidence, ATT_SLA_OUTCOME, SlaOutcome, MAX_RULES } from "./types";
import type { Policy, Rule } from "./types";

export type SlaSeverity = (typeof SlaOutcome)[keyof typeof SlaOutcome];

// The refund granted at each severity, in basis points. Published in the policy
// metadata and pinned by policyHash through the rules array, so a buyer reads the
// whole ladder before it pays.
export const DEFAULT_SLA_LADDER: Record<SlaSeverity, number> = {
  [SlaOutcome.Clean]: 0,
  [SlaOutcome.Minor]: 1_000,
  [SlaOutcome.Moderate]: 2_500,
  [SlaOutcome.Severe]: 5_000,
  [SlaOutcome.Total]: 10_000,
};

export class AgentPolicyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AgentPolicyError";
  }
}

// Quantises an observed failure rate into the bucket the attestor signs.
//
// Cross-multiplied rather than dividing, because the attestor and the buyer
// derive this independently and must land on the same bucket every time. Binary
// floating point makes the boundary cases (1/20, 5/20, 15/20) a coin flip;
// integer comparison makes them exact.
export function severity(failed: number, total: number): SlaSeverity {
  if (!Number.isInteger(failed) || !Number.isInteger(total)) {
    throw new AgentPolicyError("failed and total must be integers.");
  }
  if (total <= 0) {
    throw new AgentPolicyError("total must be positive; a session with no calls is NOT_SERVED, not a partial failure.");
  }
  if (failed < 0 || failed > total) {
    throw new AgentPolicyError(`failed must be within [0, ${total}] (got ${failed}).`);
  }

  if (failed === 0) return SlaOutcome.Clean;
  if (failed * 100 <= total * 5) return SlaOutcome.Minor;
  if (failed * 100 <= total * 25) return SlaOutcome.Moderate;
  if (failed * 100 <= total * 75) return SlaOutcome.Severe;
  return SlaOutcome.Total;
}

export interface AgentPolicyOptions {
  merchant: `0x${string}`;
  disputeWindowSeconds: number;
  // Defaults to the dispute window. Split them only when a claim should expire
  // sooner than the window in which any claim may be filed.
  claimWindowSeconds?: number;
  // What happens when the attestor is silent, which is a liveness question rather
  // than a fairness one given the attestor cannot be the merchant. 5000 is the
  // neutral split; a service competing on trust publishes higher.
  defaultRefundBps?: number;
  ladder?: Record<SlaSeverity, number>;
}

// The standard agent service policy: a severity ladder for partial failures, plus
// three mechanical claims that need no attestation because the evidence alone
// settles them.
//
// Rule order is load bearing. The engine takes the first match, so the attested
// ladder is declared before anything broader.
export function agentServicePolicy(options: AgentPolicyOptions): Policy {
  const {
    merchant,
    disputeWindowSeconds,
    claimWindowSeconds = disputeWindowSeconds,
    defaultRefundBps = 5_000,
    ladder = DEFAULT_SLA_LADDER,
  } = options;

  if (!/^0x[0-9a-fA-F]{40}$/.test(merchant)) {
    throw new AgentPolicyError("merchant must be a 20-byte hex address.");
  }
  for (const [name, value] of Object.entries({ disputeWindowSeconds, claimWindowSeconds, defaultRefundBps })) {
    if (!Number.isInteger(value) || value < 0) {
      throw new AgentPolicyError(`${name} must be a non-negative integer.`);
    }
  }
  if (defaultRefundBps > 10_000) {
    throw new AgentPolicyError("defaultRefundBps must be at most 10000.");
  }

  const severities: SlaSeverity[] = [
    SlaOutcome.Clean,
    SlaOutcome.Minor,
    SlaOutcome.Moderate,
    SlaOutcome.Severe,
    SlaOutcome.Total,
  ];

  const rules: Rule[] = severities.map((level) => {
    const refundBps = ladder[level];
    if (!Number.isInteger(refundBps) || refundBps < 0 || refundBps > 10_000) {
      throw new AgentPolicyError(`ladder[${level}] must be an integer in [0, 10000].`);
    }
    return {
      claimType: AgentClaimType.PartialFailure,
      requiredEvidenceMask: AgentEvidence.CallLogRoot,
      attType: ATT_SLA_OUTCOME,
      attExpected: level,
      claimWindow: claimWindowSeconds,
      refundBps,
      requiresReturn: false,
    };
  });

  // Nothing was delivered, so there is no call log to grade and no attestation to
  // wait for. The buyer's probe record carries it alone.
  rules.push({
    claimType: AgentClaimType.NotServed,
    requiredEvidenceMask: AgentEvidence.Unreachable,
    attType: 0,
    attExpected: 0,
    claimWindow: claimWindowSeconds,
    refundBps: 10_000,
    requiresReturn: false,
  });

  // A response that does not match the advertised schema is checkable by anyone
  // holding the response and the schema, so this needs no attestor either. Both
  // bits are required so the failing response is anchored in the session log.
  rules.push({
    claimType: AgentClaimType.SchemaViolation,
    requiredEvidenceMask: AgentEvidence.CallLogRoot | AgentEvidence.SchemaFailure,
    attType: 0,
    attExpected: 0,
    claimWindow: claimWindowSeconds,
    refundBps: 10_000,
    requiresReturn: false,
  });

  // Served correctly but too slowly. The output still has value, so this is a
  // partial refund and it does need the attestor to confirm the timing.
  rules.push({
    claimType: AgentClaimType.SlaBreach,
    requiredEvidenceMask: AgentEvidence.SlaMeasurement,
    attType: ATT_SLA_OUTCOME,
    attExpected: SlaOutcome.Moderate,
    claimWindow: claimWindowSeconds,
    refundBps: 2_500,
    requiresReturn: false,
  });

  if (rules.length > MAX_RULES) {
    throw new AgentPolicyError(`A policy allows at most ${MAX_RULES} rules (got ${rules.length}).`);
  }

  return { merchant, disputeWindow: disputeWindowSeconds, defaultRefundBps, rules };
}
