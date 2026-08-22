// Runnable attestor against an evidence host that already exists somewhere else.
//
//   ops/attestor.sh                          # against Arc, from deployments
//   ATTESTOR_RPC=... ops/attestor.sh --once  # one sweep and exit
//
// Use attestor-service.ts instead to run the attestor and its evidence host as one
// deployable process.
//
// The signing key is read from the environment and never logged.

import { runDaemon, sweepOnce } from "../src/attestor-daemon";
import { buildAttestor, configFromEnv } from "./attestor-wiring";

const key = process.env.ATTESTOR_KEY;
if (!key) throw new Error("ATTESTOR_KEY is required");

const config = configFromEnv();
const { deps, address } = buildAttestor(config, key as `0x${string}`);

console.log(`[attestor] ${address} watching ${config.escrow} on chain ${config.chainId}`);
console.log(`[attestor] evidence host ${config.evidenceBase}`);

if (process.argv.includes("--once")) {
  const summary = await sweepOnce(deps);
  console.log(`[attestor] seen ${summary.seen}, attested ${summary.attested.length}, skipped ${summary.skipped.length}`);
} else {
  const controller = new AbortController();
  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.on(signal, () => {
      console.log("[attestor] stopping");
      controller.abort();
    });
  }
  await runDaemon(deps, { intervalMs: config.intervalMs, signal: controller.signal });
}
