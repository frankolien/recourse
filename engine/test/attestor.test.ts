import { describe, it, expect } from "vitest";
import { reviewSession, parsePublishedSession } from "../src/attestor";
import { SessionRecorder, callLogRoot, countFailed } from "../src/session";
import type { CallRecord } from "../src/session";
import { SlaOutcome } from "../src/types";
import { ATT_SLA_OUTCOME } from "../src/types";

const SESSION = `0x${"c3".repeat(32)}` as const;

const call = (i: number, over: Partial<CallRecord> = {}): CallRecord => ({
  requestHash: `0x${(0xa0000000 + i).toString(16).padStart(64, "0")}`,
  responseHash: `0x${(0xb0000000 + i).toString(16).padStart(64, "0")}`,
  statusCode: 200,
  latencyMs: 120,
  schemaValid: true,
  ...over,
});

// What a buyer would publish: plain JSON, round tripped, because that is all the
// attestor ever receives.
function publish(calls: CallRecord[]) {
  const recorder = new SessionRecorder(SESSION);
  for (const c of calls) recorder.record(c);
  const draft = recorder.draft();
  return {
    published: JSON.parse(JSON.stringify(recorder.publish())),
    // What the escrow stores: the fold over the evidence items, not over the log.
    filed: draft.evidenceRoot,
    root: recorder.root,
    recorder,
  };
}

describe("attestor reviews only what was published", () => {
  it("agrees with the buyer on an honest log without seeing the buyer", () => {
    const calls = Array.from({ length: 20 }, (_, i) =>
      i % 4 === 3 ? call(i, { statusCode: 503, schemaValid: false }) : call(i),
    );
    const { published, filed, root, recorder } = publish(calls);

    const review = reviewSession(published, filed);
    expect(review.attestable).toBe(true);
    if (!review.attestable) return;

    expect(review.root).toBe(root);
    expect(review.failed).toBe(recorder.failed);
    expect(review.total).toBe(recorder.length);
    expect(review.attType).toBe(ATT_SLA_OUTCOME);
    expect(review.attValue).toBe(SlaOutcome.Moderate); // exactly 5 of 20
  });

  // The attack the root exists to stop: a buyer files one log and then publishes a
  // worse one, hoping the attestor grades what it was handed.
  it("refuses a log that does not reproduce the filed root", () => {
    const honest = publish(Array.from({ length: 20 }, (_, i) => call(i)));

    const doctored = publish(
      Array.from({ length: 20 }, (_, i) => call(i, { statusCode: 503, schemaValid: false })),
    );
    const review = reviewSession(doctored.published, honest.filed);

    expect(review.attestable).toBe(false);
    if (review.attestable) return;
    expect(review.reason).toContain("does not reproduce the root");
  });

  // Even a single flipped field has to break it, or the log is not really pinned.
  it("catches a one-call edit", () => {
    const calls = Array.from({ length: 10 }, (_, i) => call(i));
    const { published, filed } = publish(calls);
    published.calls[4].statusCode = 500;

    const review = reviewSession(published, filed);
    expect(review.attestable).toBe(false);
  });

  it("catches reordering, since the fold is order dependent", () => {
    const calls = Array.from({ length: 6 }, (_, i) => call(i));
    const { published, filed } = publish(calls);
    published.calls.reverse();

    expect(reviewSession(published, filed).attestable).toBe(false);
  });

  it("refuses an empty session rather than grading it clean", () => {
    const review = reviewSession({ sessionId: SESSION, calls: [], items: [] }, `0x${"00".repeat(32)}`);
    expect(review.attestable).toBe(false);
    if (review.attestable) return;
    expect(review.reason).toContain("NOT_SERVED");
  });

  it("rejects malformed input instead of coercing it", () => {
    const root = `0x${"11".repeat(32)}` as const;
    expect(reviewSession(null, root).attestable).toBe(false);
    expect(reviewSession({ sessionId: "0xshort", calls: [], items: [] }, root).attestable).toBe(false);
    expect(reviewSession({ sessionId: SESSION, calls: [{ requestHash: "0xzz" }], items: [] }, root).attestable).toBe(false);
    expect(
      reviewSession({ sessionId: SESSION, calls: [{ ...call(0), statusCode: -1 }], items: [] }, root).attestable,
    ).toBe(false);
  });

  it("parses a published session round tripped through JSON", () => {
    const { published } = publish([call(0), call(1)]);
    const parsed = parsePublishedSession(published);
    expect(parsed.sessionId).toBe(SESSION);
    expect(parsed.calls).toHaveLength(2);
    expect(callLogRoot(parsed.calls)).toBe(callLogRoot([call(0), call(1)]));
  });
});

describe("failure counting is shared, not duplicated", () => {
  // If the buyer and the attestor could disagree on what failed, the attestor
  // would sign a bucket the buyer never expected.
  it("gives the same answer through both entry points", () => {
    const calls = [
      call(0),
      call(1, { statusCode: 503 }),
      call(2, { schemaValid: false }),
      call(3, { latencyMs: 90_000 }), // slow is SLA_BREACH, not a failure here
      call(4, { statusCode: 301 }),
    ];
    const { published, filed, recorder } = publish(calls);
    const review = reviewSession(published, filed);

    expect(countFailed(calls)).toBe(3);
    expect(recorder.failed).toBe(3);
    if (review.attestable) expect(review.failed).toBe(3);
  });
});
