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
