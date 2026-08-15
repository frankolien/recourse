import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { callLogRoot, evidenceRoot, evidenceMask, SessionRecorder, SessionError } from "../src/session";
import type { CallRecord, EvidenceItem } from "../src/session";
import { AgentClaimType, AgentEvidence, SlaOutcome } from "../src/types";

const here = dirname(fileURLToPath(import.meta.url));
const vectorsDir = join(here, "../../packages/vectors");

interface Fixtures {
  sessions: Record<string, { calls: Record<string, unknown[]> }>;
  evidence: Record<string, { items: { evType: number[]; hash: `0x${string}`[] } }>;
}
interface Roots {
  sessions: Record<string, string>;
  evidence: Record<string, { evidenceRoot: string; evidenceMask: number }>;
}

const fixtures = JSON.parse(readFileSync(join(vectorsDir, "sessions.json"), "utf8")) as Fixtures;
const roots = JSON.parse(readFileSync(join(vectorsDir, "session-roots.json"), "utf8")) as Roots;

// Fixtures are struct-of-arrays because forge's JSONPath cannot express `[*]`
// over an empty array. Rebuild the records the module consumes.
function toCalls(raw: Record<string, unknown[]>): CallRecord[] {
  return (raw.requestHash as `0x${string}`[]).map((requestHash, k) => ({
    requestHash,
    responseHash: (raw.responseHash as `0x${string}`[])[k]!,
    statusCode: (raw.statusCode as number[])[k]!,
    latencyMs: (raw.latencyMs as number[])[k]!,
    schemaValid: (raw.schemaValid as boolean[])[k]!,
  }));
}

function toItems(raw: { evType: number[]; hash: `0x${string}`[] }): EvidenceItem[] {
  return raw.evType.map((evType, k) => ({ evType, hash: raw.hash[k]! }));
}

const hash = (v: string) => v.toLowerCase();

// The differential test. Solidity generated session-roots.json; if this module
// folds differently, a buyer and a merchant would derive different roots from the
// same log and no dispute could be verified by either.
describe("call log fold matches the Solidity implementation", () => {
  const names = Object.keys(fixtures.sessions);

  it("loads both shared files", () => {
    expect(names.length).toBeGreaterThan(0);
    expect(Object.keys(roots.sessions).sort()).toEqual([...names].sort());
  });

  for (const name of names) {
    it(name, () => {
      expect(hash(callLogRoot(toCalls(fixtures.sessions[name]!.calls)))).toBe(hash(roots.sessions[name]!));
    });
  }
});

describe("evidence fold matches what fileDispute stores", () => {
  const names = Object.keys(fixtures.evidence);

  for (const name of names) {
    it(name, () => {
      const items = toItems(fixtures.evidence[name]!.items);
      expect(hash(evidenceRoot(items))).toBe(hash(roots.evidence[name]!.evidenceRoot));
      expect(evidenceMask(items)).toBe(roots.evidence[name]!.evidenceMask);
    });
  }

  it("keeps the mask order independent and the root order dependent", () => {
    const forward = toItems(fixtures.evidence["evidence-log-and-schema"]!.items);
    const swapped = toItems(fixtures.evidence["evidence-order-swapped"]!.items);
    expect(evidenceMask(forward)).toBe(evidenceMask(swapped));
    expect(evidenceRoot(forward)).not.toBe(evidenceRoot(swapped));
  });
});

const clean = (i: number): CallRecord => ({
  requestHash: `0x${(0xa0000000 + i).toString(16).padStart(64, "0")}`,
  responseHash: `0x${(0xb0000000 + i).toString(16).padStart(64, "0")}`,
  statusCode: 200,
  latencyMs: 120,
  schemaValid: true,
});

describe("session recorder", () => {
  it("counts a call as failed on transport or schema, but not on latency", () => {
    const r = new SessionRecorder(`0x${"11".repeat(32)}`);
    r.record(clean(0));
    r.record({ ...clean(1), statusCode: 503 });
    r.record({ ...clean(2), schemaValid: false });
    r.record({ ...clean(3), latencyMs: 90_000 }); // slow is SLA_BREACH, a different claim
    expect(r.length).toBe(4);
    expect(r.failed).toBe(2);
  });

  it("derives the same root as the standalone fold", () => {
    const calls = [clean(0), clean(1), clean(2)];
    const r = new SessionRecorder(`0x${"22".repeat(32)}`);
    for (const c of calls) r.record(c);
    expect(r.root).toBe(callLogRoot(calls));
  });

  it("drafts a partial failure carrying the log root and the attested severity", () => {
    const r = new SessionRecorder(`0x${"33".repeat(32)}`);
    for (let i = 0; i < 20; i++) r.record(i % 4 === 3 ? { ...clean(i), statusCode: 503, schemaValid: false } : clean(i));

    const draft = r.draft();
    expect(draft.claimType).toBe(AgentClaimType.PartialFailure);
    expect(draft.failed).toBe(5);
    expect(draft.total).toBe(20);
    expect(draft.severity).toBe(SlaOutcome.Moderate); // exactly 0.25
    expect(draft.items).toHaveLength(1);
    expect(draft.items[0]!.evType).toBe(AgentEvidence.CallLogRoot);
    expect(draft.items[0]!.hash).toBe(r.root);
    expect(draft.evidenceRoot).toBe(evidenceRoot(draft.items));
  });

  // A rule requiring the schema bit must not match a session that cannot supply
  // it, so the item is attached only when there is a failure to anchor.
  it("attaches the schema failure item only when one exists and a schema is given", () => {
    const schemaId = `0x${"44".repeat(32)}` as const;

    const allGood = new SessionRecorder(`0x${"55".repeat(32)}`);
    allGood.record(clean(0));
    expect(allGood.draft(schemaId).evidenceMask).toBe(AgentEvidence.CallLogRoot);

    const withFailure = new SessionRecorder(`0x${"66".repeat(32)}`);
    withFailure.record(clean(0));
    withFailure.record({ ...clean(1), schemaValid: false });
    expect(withFailure.draft(schemaId).evidenceMask).toBe(AgentEvidence.CallLogRoot | AgentEvidence.SchemaFailure);
    expect(withFailure.draft().evidenceMask).toBe(AgentEvidence.CallLogRoot);
  });

  it("refuses to draft an empty session", () => {
    expect(() => new SessionRecorder(`0x${"77".repeat(32)}`).draft()).toThrow(SessionError);
  });

  it("rejects records that would not encode to the fixed widths", () => {
    const r = new SessionRecorder(`0x${"88".repeat(32)}`);
    expect(() => r.record({ ...clean(0), statusCode: 70_000 })).toThrow(SessionError);
    expect(() => r.record({ ...clean(0), latencyMs: -1 })).toThrow(SessionError);
    expect(() => r.record({ ...clean(0), requestHash: "0xdeadbeef" as never })).toThrow(SessionError);
    expect(r.length).toBe(0);
  });

  it("rejects a malformed session id", () => {
    expect(() => new SessionRecorder("0xshort" as never)).toThrow(SessionError);
  });
});
