// The attestor as a deployable service: an evidence host buyers can publish to,
// and the daemon that watches Arc for disputes against it.
//
// Both halves exist because either one alone attests to nothing. A daemon with no
// evidence host has nothing to fetch, and a host nobody watches just stores files
// while every dispute expires into defaultRefundBps.
//
// They are colocated for deployment, not for trust. The daemon fetches over HTTP
// like any other client, and reviewSession checks what comes back against the root
// the buyer already filed on chain, so this process cannot attest to a log it made
// up. Splitting the two later is a config change.
//
// The signing key is read from the environment and never logged.

import { createServer } from "node:http";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { runDaemon } from "../src/attestor-daemon";
import { handleRequest, type PublicationStore } from "../src/evidence-host";
import { buildAttestor, configFromEnv } from "./attestor-wiring";

const PORT = Number(process.env.PORT ?? 8788);
const EVIDENCE_DIR = process.env.EVIDENCE_DIR ?? "/data/agent-evidence";
const WRITE_TOKEN = process.env.EVIDENCE_WRITE_TOKEN;
const HOST_ONLY = process.argv.includes("--host-only");

// A published session is a few hundred bytes per call. This is far above any real
// one and exists so an unbounded body cannot exhaust the process.
const MAX_BODY = 4 * 1024 * 1024;

const SESSION_ID = /^0x[0-9a-f]{64}$/;

/**
 * Disk rather than memory because a restart during a dispute window would
 * otherwise lose the publication, and a lost publication is an unattested
 * dispute. On Railway this path is the mounted volume.
 */
class FilePublicationStore implements PublicationStore {
  constructor(private readonly dir: string) {}

  private path(sessionId: string): string {
    // handleRequest validates the id before reaching a store, but this is the
    // boundary where a string becomes a filesystem path, so it is checked here too.
    if (!SESSION_ID.test(sessionId)) throw new Error("refusing a session id that is not 32 bytes of hex");
    return join(this.dir, `${sessionId}.json`);
  }

  async read(sessionId: string): Promise<string | null> {
    try {
      return await readFile(this.path(sessionId), "utf8");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw error;
    }
  }

  async write(sessionId: string, body: string): Promise<void> {
    await writeFile(this.path(sessionId), body, { encoding: "utf8", flag: "wx" });
  }
}

async function readBody(stream: NodeJS.ReadableStream): Promise<string | null> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of stream) {
    size += (chunk as Buffer).length;
    if (size > MAX_BODY) return null;
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks).toString("utf8");
}

// Fail loudly on an unwritable directory rather than degrading to memory: a host
// that silently forgets is worse than one that will not start.
await mkdir(EVIDENCE_DIR, { recursive: true });
const store = new FilePublicationStore(EVIDENCE_DIR);

const server = createServer(async (req, res) => {
  const send = (status: number, body: string) => {
    res.writeHead(status, { "content-type": "application/json", "content-length": Buffer.byteLength(body) });
    res.end(body);
  };

  try {
    const body = await readBody(req);
    if (body === null) return send(413, JSON.stringify({ error: "body too large" }));

    const authorization = req.headers.authorization;
    const response = await handleRequest(
      store,
      {
        method: req.method ?? "GET",
        path: req.url ?? "/",
        body,
        token: authorization?.replace(/^Bearer /i, ""),
      },
      { writeToken: WRITE_TOKEN },
    );
    if (response.status === 201) console.log(`[evidence] stored ${req.url}`);
    send(response.status, response.body);
  } catch (error) {
    // Two writers racing the same session: handleRequest saw no file, both tried to
    // create one, and the exclusive flag settled it. Same answer as the checked path.
    if ((error as NodeJS.ErrnoException).code === "EEXIST") {
      return send(409, JSON.stringify({ error: "this session is already published and publications are immutable" }));
    }
    console.error(`[evidence] ${(error as Error).message}`);
    send(500, JSON.stringify({ error: "internal error" }));
  }
});

// No host argument, so Node binds every interface on both stacks. Railway routes to
// the container over IPv6, and binding 127.0.0.1 here is what crash-looped the
// backend the first time it was deployed.
await new Promise<void>((resolve) => server.listen(PORT, resolve));
console.log(`[evidence] listening on ${PORT}, storing in ${EVIDENCE_DIR}`);
console.log(`[evidence] publishing ${WRITE_TOKEN ? "requires a write token" : "is open, set EVIDENCE_WRITE_TOKEN to close it"}`);

const controller = new AbortController();
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    console.log("[attestor] stopping");
    controller.abort();
    server.close();
  });
}

if (HOST_ONLY) {
  console.log("[attestor] host only, not watching for disputes");
} else {
  const key = process.env.ATTESTOR_KEY;
  if (!key) throw new Error("ATTESTOR_KEY is required, or pass --host-only to serve evidence without attesting");

  // Defaults to this process's own evidence host, but stays a URL so the two can be
  // separated without touching code.
  process.env.ATTESTOR_EVIDENCE_URL ??= `http://127.0.0.1:${PORT}`;
  const config = configFromEnv();
  const { deps, address } = buildAttestor(config, key as `0x${string}`);

  console.log(`[attestor] ${address} watching ${config.escrow} on chain ${config.chainId}`);
  console.log(`[attestor] reading evidence from ${config.evidenceBase}`);

  // Deliberately not awaited: the server has to keep answering healthchecks and
  // publications while the daemon polls.
  runDaemon(deps, { intervalMs: config.intervalMs, signal: controller.signal }).catch((error) => {
    console.error(`[attestor] daemon stopped: ${(error as Error).message}`);
    process.exitCode = 1;
    server.close();
  });
}
