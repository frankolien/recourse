// The attestor's whole job, docs/agent-settlement.md sections A2 and 5.4.
//
// It is deliberately given nothing but the published session log and the root the
// buyer already committed to on chain. It never sees the buyer's process, its
// memory, or its claim about how many calls failed. That is the point: an attestor
// that trusts the disputing party is not attesting to anything.
//
// It also never decides a refund. It derives one number, the severity bucket, from
// bytes anyone else can recheck. The refund was fixed by the policy before payment,
// and the engine selects it.

import { callLogRoot, countFailed, evidenceRoot, SessionError } from "./session";
import type { CallRecord, EvidenceItem } from "./session";
import { AgentEvidence } from "./types";
import { severity } from "./agent";
import type { SlaSeverity } from "./agent";
import { ATT_SLA_OUTCOME } from "./types";

/**
 * What a buyer publishes so its dispute can be checked. The evidence items are
 * part of it because the chain stores only their fold, so without them there is
 * nothing to tie the log to what was filed.
 */
export interface PublishedSession {
  sessionId: `0x${string}`;
  calls: CallRecord[];
  items: EvidenceItem[];
}

export type SessionReview =
  | {
      attestable: true;
      attType: number;
      attValue: SlaSeverity;
      failed: number;
      total: number;
      root: `0x${string}`;
    }
  | { attestable: false; reason: string; root: `0x${string}` | null };

/**
 * Two checks against the one value the chain actually stores, then the severity.
 *
 * The escrow keeps `evidenceRoot`, a fold over the evidence items, and nothing
 * else about the session. So the items must first reproduce that fold, and the
 * CALL_LOG_ROOT item among them must then reproduce the fold over the calls. Only
 * a log that survives both is the log the dispute was filed against.
 *
 * A mismatch is refused rather than graded clean. Grading it would let a buyer
 * file one log and publish a different one to draw a better attestation, and a
 * CLEAN signature on a session nobody can verify is worse than no signature.
 */
export function reviewSession(published: unknown, filedEvidenceRoot: `0x${string}`): SessionReview {
  let session: PublishedSession;
  try {
    session = parsePublishedSession(published);
  } catch (error) {
    return { attestable: false, reason: (error as Error).message, root: null };
  }

  const { calls, items } = session;
  if (calls.length === 0) {
    return { attestable: false, reason: "published session has no calls; that is NOT_SERVED, not a partial failure", root: null };
  }

  let root: `0x${string}`;
  try {
    if (evidenceRoot(items).toLowerCase() !== filedEvidenceRoot.toLowerCase()) {
      return { attestable: false, reason: "published evidence does not reproduce the root filed on chain", root: null };
    }
    root = callLogRoot(calls);
  } catch (error) {
    return { attestable: false, reason: (error as Error).message, root: null };
  }

  const logItem = items.find((i) => i.evType === AgentEvidence.CallLogRoot);
  if (!logItem) {
    return { attestable: false, reason: "filed evidence carries no CALL_LOG_ROOT item", root };
  }
  if (root.toLowerCase() !== logItem.hash.toLowerCase()) {
    return { attestable: false, reason: "published log does not reproduce the root filed on chain", root };
  }

  const failed = countFailed(calls);
  return {
    attestable: true,
    attType: ATT_SLA_OUTCOME,
    attValue: severity(failed, calls.length),
    failed,
    total: calls.length,
    root,
  };
}

/** Strict, because this is the one place untrusted bytes enter the attestor. */
export function parsePublishedSession(value: unknown): PublishedSession {
  if (!value || typeof value !== "object") {
    throw new SessionError("published session must be an object.");
  }
  const raw = value as Record<string, unknown>;
  if (typeof raw.sessionId !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(raw.sessionId)) {
    throw new SessionError("published session sessionId must be a 32-byte hex string.");
  }
  if (!Array.isArray(raw.calls)) {
    throw new SessionError("published session calls must be an array.");
  }

  const calls = raw.calls.map((entry, index) => {
    if (!entry || typeof entry !== "object") {
      throw new SessionError(`published call ${index} is not an object.`);
    }
    const c = entry as Record<string, unknown>;
    const hex = (key: string): `0x${string}` => {
      const v = c[key];
      if (typeof v !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(v)) {
        throw new SessionError(`published call ${index} field ${key} must be a 32-byte hex string.`);
      }
      return v as `0x${string}`;
    };
    const int = (key: string): number => {
      const v = c[key];
      if (typeof v !== "number" || !Number.isInteger(v) || v < 0) {
        throw new SessionError(`published call ${index} field ${key} must be a non-negative integer.`);
      }
      return v;
    };
    if (typeof c.schemaValid !== "boolean") {
      throw new SessionError(`published call ${index} field schemaValid must be a boolean.`);
    }
    return {
      requestHash: hex("requestHash"),
      responseHash: hex("responseHash"),
      statusCode: int("statusCode"),
      latencyMs: int("latencyMs"),
      schemaValid: c.schemaValid,
    };
  });

  if (!Array.isArray(raw.items)) {
    throw new SessionError("published session items must be an array.");
  }
  const items = raw.items.map((entry, index) => {
    const i = entry as Record<string, unknown>;
    if (!i || typeof i !== "object") throw new SessionError(`published item ${index} is not an object.`);
    if (typeof i.evType !== "number" || !Number.isInteger(i.evType) || i.evType < 0 || i.evType > 255) {
      throw new SessionError(`published item ${index} evType must be a byte.`);
    }
    if (typeof i.hash !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(i.hash)) {
      throw new SessionError(`published item ${index} hash must be a 32-byte hex string.`);
    }
    return { evType: i.evType, hash: i.hash as `0x${string}` };
  });

  return { sessionId: raw.sessionId as `0x${string}`, calls, items };
}
