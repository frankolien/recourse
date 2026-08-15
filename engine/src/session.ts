// Session recording and evidence derivation, docs/agent-settlement.md section A4.
//
// Two separate chains live here and they are easy to confuse:
//
//   callLogRoot   folds every call in a session into one hash. Purely off chain;
//                 the contract never sees it except as an evidence item hash.
//   evidenceRoot  reproduces the fold RecourseEscrow.fileDispute runs over the
//                 EvidenceItem array. Lets a buyer predict what will be stored,
//                 and lets the merchant and attestor recheck it afterwards.
//
// Both are chained folds rather than Merkle trees, matching the contract, so an
// item cannot be proved in isolation. That is deliberate: the full log is
// published anyway, and the root exists to pin it, not to prove parts of it.

import { encodeAbiParameters, encodePacked, keccak256 } from "viem";
import { callRecordParams } from "./abi";
import { AgentClaimType, AgentEvidence } from "./types";
import { severity, type SlaSeverity } from "./agent";

export interface CallRecord {
  // Hash of the canonicalised request, so the log pins what was asked without
  // republishing bodies that may hold secrets.
  requestHash: `0x${string}`;
  responseHash: `0x${string}`;
  statusCode: number;
  latencyMs: number;
  schemaValid: boolean;
}

export interface EvidenceItem {
  evType: number;
  hash: `0x${string}`;
}

export class SessionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SessionError";
  }
}

const U16_MAX = 65_535;
const U32_MAX = 4_294_967_295;
const ZERO_ROOT = `0x${"0".repeat(64)}` as const;

function requireBytes32(value: string, label: string): `0x${string}` {
  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) {
    throw new SessionError(`${label} must be a 32-byte hex string.`);
  }
  return value.toLowerCase() as `0x${string}`;
}

export function callHash(record: CallRecord, index: number): `0x${string}` {
  if (!Number.isInteger(index) || index < 0) {
    throw new SessionError("index must be a non-negative integer.");
  }
  if (!Number.isInteger(record.statusCode) || record.statusCode < 0 || record.statusCode > U16_MAX) {
    throw new SessionError(`statusCode must be an integer in [0, ${U16_MAX}].`);
  }
  if (!Number.isInteger(record.latencyMs) || record.latencyMs < 0 || record.latencyMs > U32_MAX) {
    throw new SessionError(`latencyMs must be an integer in [0, ${U32_MAX}].`);
  }
  if (typeof record.schemaValid !== "boolean") {
    throw new SessionError("schemaValid must be a boolean.");
  }

  return keccak256(
    encodeAbiParameters(callRecordParams, [
      BigInt(index),
      requireBytes32(record.requestHash, "requestHash"),
      requireBytes32(record.responseHash, "responseHash"),
      record.statusCode,
      record.latencyMs,
      record.schemaValid,
    ]),
  );
}

// L[0] = 0; L[i] = keccak256(abi.encodePacked(L[i-1], h[i])).
// An empty session yields the zero root, which is why NOT_SERVED is a separate
// claim: there is no log to grade, so the root carries no information.
export function callLogRoot(records: readonly CallRecord[]): `0x${string}` {
  let root: `0x${string}` = ZERO_ROOT;
  for (let i = 0; i < records.length; i++) {
    root = keccak256(encodePacked(["bytes32", "bytes32"], [root, callHash(records[i]!, i)]));
  }
  return root;
}

// Mirror of the fold inside RecourseEscrow.fileDispute. Unlike callHash, this is
// packed rather than abi.encoded, so the declared width does change the bytes:
// evType is uint8 on chain, and widening it here shifts every following byte and
// yields a different root. Verified by mutation, not by reading.
export function evidenceRoot(items: readonly EvidenceItem[]): `0x${string}` {
  let root: `0x${string}` = ZERO_ROOT;
  for (const item of items) {
    if (!Number.isInteger(item.evType) || item.evType < 0 || item.evType > 255) {
      throw new SessionError("evType must be an integer in [0, 255].");
    }
    root = keccak256(
      encodePacked(["bytes32", "uint8", "bytes32"], [root, item.evType, requireBytes32(item.hash, "evidence hash")]),
    );
  }
  return root;
}

export function evidenceMask(items: readonly EvidenceItem[]): number {
  return items.reduce((mask, item) => mask | item.evType, 0);
}

export interface DisputeDraft {
  claimType: number;
  items: EvidenceItem[];
  evidenceMask: number;
  evidenceRoot: `0x${string}`;
  // What the attestor is expected to sign, derived from the same log the buyer
  // publishes. Present so both sides can compare before anything is filed.
  severity: SlaSeverity;
  failed: number;
  total: number;
}

// Accumulates calls and produces the dispute the buyer would file. Kept as a
// class because a session is inherently stateful and the ordering of records is
// what the root commits to.
export class SessionRecorder {
  private readonly records: CallRecord[] = [];
  private firstSchemaFailure: { index: number; record: CallRecord } | null = null;

  constructor(readonly sessionId: `0x${string}`) {
    requireBytes32(sessionId, "sessionId");
  }

  record(call: CallRecord): void {
    const index = this.records.length;
    callHash(call, index); // validates before it is committed to the log
    this.records.push(call);
    if (!this.firstSchemaFailure && !call.schemaValid) {
      this.firstSchemaFailure = { index, record: call };
    }
  }

  get length(): number {
    return this.records.length;
  }

  // A call counts as failed when the transport failed or the body did not match
  // the advertised schema. Latency is deliberately excluded: being slow is
  // SLA_BREACH, a different claim with a different refund.
  get failed(): number {
    return this.records.filter((r) => r.statusCode < 200 || r.statusCode >= 300 || !r.schemaValid).length;
  }

  get root(): `0x${string}` {
    return callLogRoot(this.records);
  }

  toJSON(): { sessionId: `0x${string}`; calls: CallRecord[] } {
    return { sessionId: this.sessionId, calls: [...this.records] };
  }

  // Builds the PARTIAL_FAILURE dispute. The schema failure item is included only
  // when there is one, because a rule requiring that bit must not match a session
  // that cannot supply it.
  draft(schemaId?: `0x${string}`): DisputeDraft {
    if (this.records.length === 0) {
      throw new SessionError("an empty session is NOT_SERVED, not a partial failure.");
    }

    const items: EvidenceItem[] = [{ evType: AgentEvidence.CallLogRoot, hash: this.root }];

    if (this.firstSchemaFailure && schemaId) {
      items.push({
        evType: AgentEvidence.SchemaFailure,
        hash: keccak256(
          encodePacked(
            ["bytes32", "bytes32"],
            [requireBytes32(this.firstSchemaFailure.record.responseHash, "responseHash"), requireBytes32(schemaId, "schemaId")],
          ),
        ),
      });
    }

    const failed = this.failed;
    return {
      claimType: AgentClaimType.PartialFailure,
      items,
      evidenceMask: evidenceMask(items),
      evidenceRoot: evidenceRoot(items),
      severity: severity(failed, this.records.length),
      failed,
      total: this.records.length,
    };
  }
}
