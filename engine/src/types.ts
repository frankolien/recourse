// Mirror of contracts/src/Types.sol. Field names and order match the Solidity
// structs so the ABI encoding in hash.ts reproduces the on-chain hashes exactly.

export enum ClaimType {
  NotDelivered = 0,
  Damaged = 1,
  NotAsDescribed = 2,
  WrongItem = 3,
  Other = 4,
}

// Evidence bitmask: 1 = PHOTO, 2 = DESCRIPTION, 4 = TRACKING_REF, 8 = VIDEO.
// Attestation types: 0 = NONE, 1 = DELIVERY_STATUS.
// DELIVERY_STATUS values: 0 = UNKNOWN, 1 = DELIVERED, 2 = NOT_DELIVERED.

// Agent commerce vocabulary, mirroring the constants in Types.sol. Kept separate
// from ClaimType above because the parcel authoring UI types its label maps as
// total records over that enum, and widening it would break them.
export const AgentClaimType = {
  NotServed: 5,
  SchemaViolation: 6,
  SlaBreach: 7,
  PartialFailure: 8,
} as const;

export const AgentEvidence = {
  CallLogRoot: 16,
  SchemaFailure: 32,
  SlaMeasurement: 64,
  Unreachable: 128,
} as const;

export const ATT_SLA_OUTCOME = 2;

// Severity buckets for ATT_SLA_OUTCOME. Ordered worst-last so the numeric value
// rises with severity, which is what makes the refund ladder readable.
export const SlaOutcome = {
  Clean: 0,
  Minor: 1,
  Moderate: 2,
  Severe: 3,
  Total: 4,
} as const;

export interface Rule {
  claimType: number;
  requiredEvidenceMask: number;
  attType: number;
  attExpected: number;
  claimWindow: number;
  refundBps: number;
  requiresReturn: boolean;
}

export interface Policy {
  merchant: `0x${string}`;
  disputeWindow: number;
  defaultRefundBps: number;
  rules: Rule[];
}

// Timestamps are uint64 on-chain; kept as bigint here so window arithmetic and
// hashing stay exact past 2^53.
export interface VerdictInput {
  claimType: number;
  evidenceMask: number;
  attType: number;
  attValue: number;
  paidAt: bigint;
  filedAt: bigint;
}

export interface Verdict {
  refundBps: number;
  requiresReturn: boolean;
  ruleIndex: number;
  matched: boolean;
}

export const NO_RULE = 255;
export const MAX_RULES = 16;
