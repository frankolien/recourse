// Policy authoring compiler (PRD section 6). Merchants author JSON; this encodes
// it to the on-chain Policy/Rule structs. It adds no verdict logic: matching stays
// in engine.ts and the hash stays in hash.ts (R2). The policyHash covers the
// on-chain encoding, not the authored JSON, so `id` and `version` are not hashed.

import type { Policy, Rule } from "./types";
import { MAX_RULES } from "./types";

export const CLAIM_TYPE_NAMES = ["NOT_DELIVERED", "DAMAGED", "NOT_AS_DESCRIBED", "WRONG_ITEM", "OTHER"] as const;
export const EVIDENCE_NAMES = ["PHOTO", "DESCRIPTION", "TRACKING_REF", "VIDEO"] as const;
export const DELIVERY_STATUS_NAMES = ["UNKNOWN", "DELIVERED", "NOT_DELIVERED"] as const;

export type ClaimTypeName = (typeof CLAIM_TYPE_NAMES)[number];
export type EvidenceName = (typeof EVIDENCE_NAMES)[number];
export type DeliveryStatusName = (typeof DELIVERY_STATUS_NAMES)[number];

const EVIDENCE_BIT: Record<EvidenceName, number> = { PHOTO: 1, DESCRIPTION: 2, TRACKING_REF: 4, VIDEO: 8 };
const ATT_DELIVERY_STATUS = 1;

const U32_MAX = 4_294_967_295;

export interface AttestationSpec {
  type: "DELIVERY_STATUS";
  equals: DeliveryStatusName;
}

export interface RuleSpec {
  id?: string;
  claimType: ClaimTypeName;
  requiredEvidence: EvidenceName[];
  attestation: AttestationSpec | null;
  claimWindowSeconds: number;
  refundBps: number;
  requiresReturn: boolean;
}

export interface PolicySpec {
  version?: number;
  disputeWindowSeconds: number;
  defaultRefundBps: number;
  rules: RuleSpec[];
}

export class PolicyCompileError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PolicyCompileError";
  }
}

function requireIntInRange(value: unknown, min: number, max: number, label: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new PolicyCompileError(`${label} must be an integer.`);
  }
  if (value < min || value > max) {
    throw new PolicyCompileError(`${label} must be between ${min} and ${max}.`);
  }
  return value;
}

function evidenceMask(evidence: EvidenceName[], ruleLabel: string): number {
  let mask = 0;
  const seen = new Set<EvidenceName>();
  for (const name of evidence) {
    if (!(name in EVIDENCE_BIT)) {
      throw new PolicyCompileError(`${ruleLabel}: unknown evidence "${name}".`);
    }
    if (seen.has(name)) {
      throw new PolicyCompileError(`${ruleLabel}: duplicate evidence "${name}".`);
    }
    seen.add(name);
    mask |= EVIDENCE_BIT[name];
  }
  return mask;
}

function compileRule(spec: RuleSpec, index: number): Rule {
  const label = `Rule ${index + 1}`;
  const claimType = CLAIM_TYPE_NAMES.indexOf(spec.claimType);
  if (claimType < 0) {
    throw new PolicyCompileError(`${label}: unknown claim type "${spec.claimType}".`);
  }
  if (!Array.isArray(spec.requiredEvidence)) {
    throw new PolicyCompileError(`${label}: requiredEvidence must be an array.`);
  }

  let attType = 0;
  let attExpected = 0;
  if (spec.attestation !== null && spec.attestation !== undefined) {
    if (spec.attestation.type !== "DELIVERY_STATUS") {
      throw new PolicyCompileError(`${label}: unsupported attestation type "${spec.attestation.type}".`);
    }
    const value = DELIVERY_STATUS_NAMES.indexOf(spec.attestation.equals);
    if (value < 0) {
      throw new PolicyCompileError(`${label}: unknown delivery status "${spec.attestation.equals}".`);
    }
    attType = ATT_DELIVERY_STATUS;
    attExpected = value;
  }

  if (typeof spec.requiresReturn !== "boolean") {
    throw new PolicyCompileError(`${label}: requiresReturn must be a boolean.`);
  }

  return {
    claimType,
    requiredEvidenceMask: evidenceMask(spec.requiredEvidence, label),
    attType,
    attExpected,
    claimWindow: requireIntInRange(spec.claimWindowSeconds, 0, U32_MAX, `${label}: claimWindowSeconds`),
    refundBps: requireIntInRange(spec.refundBps, 0, 10_000, `${label}: refundBps`),
    requiresReturn: spec.requiresReturn,
  };
}

// Compile an authored spec into the on-chain Policy. The merchant is supplied
// separately because on-chain it is msg.sender, not part of the authored JSON.
export function compilePolicy(spec: PolicySpec, merchant: `0x${string}`): Policy {
  if (!/^0x[0-9a-fA-F]{40}$/.test(merchant)) {
    throw new PolicyCompileError("merchant must be a 20-byte hex address.");
  }
  if (!Array.isArray(spec.rules)) {
    throw new PolicyCompileError("rules must be an array.");
  }
  if (spec.rules.length > MAX_RULES) {
    throw new PolicyCompileError(`A policy allows at most ${MAX_RULES} rules (got ${spec.rules.length}).`);
  }

  return {
    merchant,
    disputeWindow: requireIntInRange(spec.disputeWindowSeconds, 0, U32_MAX, "disputeWindowSeconds"),
    defaultRefundBps: requireIntInRange(spec.defaultRefundBps, 0, 10_000, "defaultRefundBps"),
    rules: spec.rules.map(compileRule),
  };
}

// Reverse of compilePolicy for preloading an on-chain policy into the authoring
// UI. Rule ids are not stored on-chain, so they come back undefined.
export function toSpec(policy: Policy): PolicySpec {
  return {
    version: 1,
    disputeWindowSeconds: policy.disputeWindow,
    defaultRefundBps: policy.defaultRefundBps,
    rules: policy.rules.map((rule) => ({
      claimType: CLAIM_TYPE_NAMES[rule.claimType] ?? "OTHER",
      requiredEvidence: EVIDENCE_NAMES.filter((name) => (rule.requiredEvidenceMask & EVIDENCE_BIT[name]) === EVIDENCE_BIT[name]),
      attestation: rule.attType === ATT_DELIVERY_STATUS
        ? { type: "DELIVERY_STATUS", equals: DELIVERY_STATUS_NAMES[rule.attExpected] ?? "UNKNOWN" }
        : null,
      claimWindowSeconds: rule.claimWindow,
      refundBps: rule.refundBps,
      requiresReturn: rule.requiresReturn,
    })),
  };
}
