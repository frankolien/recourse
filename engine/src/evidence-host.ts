// Where a buyer's published session actually lives, so the attestor has something
// to fetch when it is not running on the same laptop as the demo.
//
// This host is untrusted on purpose and holds no authority. Everything it serves
// is checked against the chain by reviewSession(): the items must reproduce the
// evidenceRoot the buyer filed, and the call log must reproduce the root inside
// them. A host that lies, or that is run by the attestor itself, therefore cannot
// produce a false attestation. The worst it can do is withhold, and withholding
// resolves the dispute at the policy default, which is the conservative answer.
//
// All storage is injected so the request rules below are tested without a socket
// or a filesystem.

import { parsePublishedSession } from "./attestor";
import type { PublishedSession } from "./attestor";

export interface PublicationStore {
  read(sessionId: string): Promise<string | null>;
  write(sessionId: string, body: string): Promise<void>;
}

export interface HostRequest {
  method: string;
  /** Request target, query string included; it is stripped here. */
  path: string;
  body?: string;
  /** Bearer token presented by the writer, when the host requires one. */
  token?: string;
}

export interface HostResponse {
  status: number;
  /** Already serialised, so stored bytes are served back unchanged. */
  body: string;
}

export interface HostOptions {
  /**
   * Required to publish. Without one, anyone can claim a session id before its
   * buyer does and get the honest publication refused as a conflict. That costs
   * the buyer its attestation, not its money, so this is a nuisance rather than a
   * hole, but the token closes it for a few lines.
   */
  writeToken?: string;
}

/** In-memory store. Correct for tests and for a process that may lose a restart. */
export class MemoryPublicationStore implements PublicationStore {
  private readonly entries = new Map<string, string>();

  async read(sessionId: string): Promise<string | null> {
    return this.entries.get(sessionId) ?? null;
  }

  async write(sessionId: string, body: string): Promise<void> {
    this.entries.set(sessionId, body);
  }
}

/**
 * Fixed field order and fixed types, so two publications of the same session are
 * byte-identical whatever order the buyer's JSON serialiser chose. Idempotence
 * below compares these bytes, and without canonicalising, a re-publish that
 * differed only in key order would be rejected as a conflicting rewrite.
 *
 * Dropping unknown fields is safe because they are exactly the fields no hash
 * commits to.
 */
export function canonicalPublication(session: PublishedSession): string {
  return JSON.stringify({
    sessionId: session.sessionId.toLowerCase(),
    calls: session.calls.map((c) => ({
      requestHash: c.requestHash.toLowerCase(),
      responseHash: c.responseHash.toLowerCase(),
      statusCode: c.statusCode,
      latencyMs: c.latencyMs,
      schemaValid: c.schemaValid,
    })),
    items: session.items.map((i) => ({ evType: i.evType, hash: i.hash.toLowerCase() })),
  });
}

const json = (status: number, value: unknown): HostResponse => ({
  status,
  body: JSON.stringify(value),
});

const SESSION_ID = /^0x[0-9a-fA-F]{64}$/;

/**
 * The whole host. Three routes, and the rules that matter are in PUT.
 *
 * A publication is immutable once stored. The chained hash check already stops a
 * buyer from drawing a better attestation by publishing a different log than it
 * filed, so immutability is not what makes the system sound; it is what keeps the
 * record checkable afterwards by anyone who was not watching at the time.
 */
export async function handleRequest(
  store: PublicationStore,
  request: HostRequest,
  options: HostOptions = {},
): Promise<HostResponse> {
  const path = (request.path ?? "").split("?")[0]!.replace(/\/+$/, "") || "/";

  if (path === "/health") {
    if (request.method !== "GET") return json(405, { error: "method not allowed" });
    return json(200, { ok: true });
  }

  const match = /^\/session\/(0x[0-9a-fA-F]{64})$/.exec(path);
  if (!match) {
    if (path.startsWith("/session/")) {
      return json(400, { error: "session id must be a 32-byte hex string" });
    }
    return json(404, { error: "not found" });
  }
  const sessionId = match[1]!.toLowerCase();

  if (request.method === "GET") {
    const stored = await store.read(sessionId);
    if (stored === null) return json(404, { error: "not published" });
    return { status: 200, body: stored };
  }

  if (request.method !== "PUT" && request.method !== "POST") {
    return json(405, { error: "method not allowed" });
  }

  if (options.writeToken && request.token !== options.writeToken) {
    return json(401, { error: "publishing requires the write token" });
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(request.body ?? "");
  } catch {
    return json(400, { error: "body must be JSON" });
  }

  let session: PublishedSession;
  try {
    session = parsePublishedSession(parsed);
  } catch (error) {
    return json(400, { error: (error as Error).message });
  }

  // The path is what the attestor derives from the chain's orderRef, so a body
  // filed under a different id would be unreachable no matter what it contains.
  if (session.sessionId.toLowerCase() !== sessionId) {
    return json(400, { error: "session id in the body does not match the path" });
  }

  const canonical = canonicalPublication(session);
  const existing = await store.read(sessionId);
  if (existing !== null) {
    if (existing === canonical) return json(200, { sessionId, stored: true, idempotent: true });
    return json(409, { error: "this session is already published and publications are immutable" });
  }

  await store.write(sessionId, canonical);
  return json(201, { sessionId, stored: true, calls: session.calls.length });
}

export class PublishError extends Error {}

/**
 * The buyer's side. Separate from the recorder because publishing is a deployment
 * concern: the same session may be published to a hosted endpoint, to a local one
 * during a demo, or to nothing at all when the buyer never disputes.
 */
export async function publishSession(
  baseUrl: string,
  session: PublishedSession,
  options: { token?: string; fetchImpl?: typeof fetch } = {},
): Promise<void> {
  if (!SESSION_ID.test(session.sessionId)) {
    throw new PublishError("session id must be a 32-byte hex string.");
  }
  const doFetch = options.fetchImpl ?? fetch;
  const base = baseUrl.replace(/\/$/, "");
  const response = await doFetch(`${base}/session/${session.sessionId.toLowerCase()}`, {
    method: "PUT",
    headers: {
      "content-type": "application/json",
      ...(options.token ? { authorization: `Bearer ${options.token}` } : {}),
    },
    body: canonicalPublication(session),
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new PublishError(`publishing session returned ${response.status}: ${detail}`);
  }
}
