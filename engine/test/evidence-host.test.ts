import { describe, it, expect } from "vitest";
import {
  MemoryPublicationStore,
  canonicalPublication,
  handleRequest,
  publishSession,
  PublishError,
} from "../src/evidence-host";
import { reviewSession } from "../src/attestor";
import { SessionRecorder } from "../src/session";
import type { CallRecord } from "../src/session";

const SESSION = `0x${"c3".repeat(32)}` as const;
const OTHER = `0x${"d4".repeat(32)}` as const;

const call = (i: number, over: Partial<CallRecord> = {}): CallRecord => ({
  requestHash: `0x${(0xa0000000 + i).toString(16).padStart(64, "0")}`,
  responseHash: `0x${(0xb0000000 + i).toString(16).padStart(64, "0")}`,
  statusCode: 200,
  latencyMs: 120,
  schemaValid: true,
  ...over,
});

function session(id: `0x${string}` = SESSION, count = 8) {
  const recorder = new SessionRecorder(id);
  for (let i = 0; i < count; i++) recorder.record(i % 4 === 3 ? call(i, { statusCode: 503, schemaValid: false }) : call(i));
  return { published: recorder.publish(), filed: recorder.draft().evidenceRoot };
}

const put = (body: unknown, id: string = SESSION, token?: string) => ({
  method: "PUT",
  path: `/session/${id}`,
  body: typeof body === "string" ? body : JSON.stringify(body),
  token,
});

describe("evidence host serves what the buyer published", () => {
  it("stores a publication and serves it back", async () => {
    const store = new MemoryPublicationStore();
    const { published } = session();

    const write = await handleRequest(store, put(published));
    expect(write.status).toBe(201);
    expect(JSON.parse(write.body).calls).toBe(8);

    const read = await handleRequest(store, { method: "GET", path: `/session/${SESSION}` });
    expect(read.status).toBe(200);
    expect(JSON.parse(read.body).calls).toHaveLength(8);
  });

  it("serves bytes an attestor can still verify against the filed root", async () => {
    const store = new MemoryPublicationStore();
    const { published, filed } = session();
    await handleRequest(store, put(published));

    const served = JSON.parse((await handleRequest(store, { method: "GET", path: `/session/${SESSION}` })).body);

    // The point of the whole host: a round trip through it must not disturb the
    // hashes, or every dispute would resolve to the default.
    const review = reviewSession(served, filed);
    expect(review.attestable).toBe(true);
    if (!review.attestable) return;
    expect(review.failed).toBe(2);
    expect(review.total).toBe(8);
  });

  it("404s a session nobody published", async () => {
    const store = new MemoryPublicationStore();
    const response = await handleRequest(store, { method: "GET", path: `/session/${SESSION}` });
    expect(response.status).toBe(404);
  });

  it("answers the healthcheck", async () => {
    const response = await handleRequest(new MemoryPublicationStore(), { method: "GET", path: "/health" });
    expect(response.status).toBe(200);
    expect(JSON.parse(response.body).ok).toBe(true);
  });
});

describe("evidence host refuses what it cannot stand behind", () => {
  it("rejects a body that is not a session", async () => {
    const store = new MemoryPublicationStore();
    expect((await handleRequest(store, put("not json at all"))).status).toBe(400);
    expect((await handleRequest(store, put({ sessionId: SESSION }))).status).toBe(400);
  });

  it("rejects a session filed under someone else's id", async () => {
    const store = new MemoryPublicationStore();
    const { published } = session(OTHER);

    // Reachability, not authenticity: the attestor looks this up by the orderRef
    // on chain, so a body stored under a different id could never be found.
    const response = await handleRequest(store, put(published, SESSION));
    expect(response.status).toBe(400);
    expect(JSON.parse(response.body).error).toMatch(/does not match the path/);
  });

  it("rejects a malformed session id in the path", async () => {
    const store = new MemoryPublicationStore();
    expect((await handleRequest(store, { method: "GET", path: "/session/0xdead" })).status).toBe(400);
  });

  it("accepts a republish of the same session and refuses a rewrite", async () => {
    const store = new MemoryPublicationStore();
    const { published } = session();
    expect((await handleRequest(store, put(published))).status).toBe(201);

    // A retry must not look like an attack, whatever order its keys serialised in.
    const reordered = JSON.stringify({ items: published.items, calls: published.calls, sessionId: published.sessionId });
    const again = await handleRequest(store, put(reordered));
    expect(again.status).toBe(200);
    expect(JSON.parse(again.body).idempotent).toBe(true);

    const rewritten = { ...published, calls: published.calls.map((c) => ({ ...c, latencyMs: c.latencyMs + 1 })) };
    const conflict = await handleRequest(store, put(rewritten));
    expect(conflict.status).toBe(409);
    // The original survives, so anyone rechecking the dispute later sees what was
    // actually attested to.
    const read = await handleRequest(store, { method: "GET", path: `/session/${SESSION}` });
    expect(read.body).toBe(canonicalPublication(published));
  });

  it("requires the write token when one is configured", async () => {
    const store = new MemoryPublicationStore();
    const { published } = session();
    const options = { writeToken: "s3cret" };

    expect((await handleRequest(store, put(published), options)).status).toBe(401);
    expect((await handleRequest(store, put(published, SESSION, "wrong"), options)).status).toBe(401);
    expect((await handleRequest(store, put(published, SESSION, "s3cret"), options)).status).toBe(201);
  });

  it("refuses writes it does not understand rather than storing them", async () => {
    const store = new MemoryPublicationStore();
    expect((await handleRequest(store, { method: "DELETE", path: `/session/${SESSION}` })).status).toBe(405);
    expect((await handleRequest(store, { method: "GET", path: "/" })).status).toBe(404);
  });
});

describe("buyers publish over the same contract the attestor reads", () => {
  it("PUTs the canonical bytes to the session's own path", async () => {
    const store = new MemoryPublicationStore();
    const { published, filed } = session();
    const seen: { url: string; init: RequestInit }[] = [];

    const fetchImpl = (async (url: string, init: RequestInit) => {
      seen.push({ url, init });
      const response = await handleRequest(store, {
        method: init.method!,
        path: new URL(url).pathname,
        body: init.body as string,
        token: (init.headers as Record<string, string>).authorization?.replace("Bearer ", ""),
      });
      return new Response(response.body, { status: response.status });
    }) as unknown as typeof fetch;

    await publishSession("https://attestor.example/", published, { token: "s3cret", fetchImpl });

    expect(seen[0]!.url).toBe(`https://attestor.example/session/${SESSION}`);
    expect((seen[0]!.init.headers as Record<string, string>).authorization).toBe("Bearer s3cret");

    // End to end through the client: what the buyer sent is what an attestor can verify.
    const served = JSON.parse((await handleRequest(store, { method: "GET", path: `/session/${SESSION}` })).body);
    expect(reviewSession(served, filed).attestable).toBe(true);
  });

  it("raises rather than continuing when the host refuses", async () => {
    const { published } = session();
    const fetchImpl = (async () => new Response(JSON.stringify({ error: "nope" }), { status: 409 })) as unknown as typeof fetch;

    await expect(publishSession("https://attestor.example", published, { fetchImpl })).rejects.toBeInstanceOf(PublishError);
  });
});
