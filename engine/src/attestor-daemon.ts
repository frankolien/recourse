// The attestor as something that runs, rather than a function someone remembers to
// call. This is what T4 in docs/agent-settlement.md needs: if nothing watches for
// disputes, every one of them falls through to defaultRefundBps and the severity
// ladder never fires.
//
// All chain and network access is injected, so the policy decisions below are
// tested against fakes rather than against a node.

import { reviewSession } from "./attestor";
import type { SessionReview } from "./attestor";

export interface DisputedPayment {
  paymentId: bigint;
  policyId: bigint;
  evidenceRoot: `0x${string}`;
  claimType: number;
  /** Non-zero once an attestation has landed. */
  attType: number;
  /** RecourseEscrow.Status; 2 is Disputed. */
  status: number;
}

export interface AttestorChain {
  /** Payment ids with a DisputeFiled log inside the lookback window. */
  recentDisputes(): Promise<bigint[]>;
  getPayment(paymentId: bigint): Promise<DisputedPayment | null>;
  /** The session a payment was opened for, recovered from the Paid log. */
  orderRef(paymentId: bigint): Promise<`0x${string}` | null>;
  attestorFor(policyId: bigint): Promise<`0x${string}`>;
  attestationDigest(paymentId: bigint, attType: number, value: number, deadline: bigint): Promise<`0x${string}`>;
  submitAttestation(
    paymentId: bigint, attType: number, value: number, deadline: bigint, signature: `0x${string}`,
  ): Promise<`0x${string}`>;
}

export interface AttestorDeps {
  chain: AttestorChain;
  /** Fetches the buyer's published bundle for a session. */
  fetchSession(sessionId: `0x${string}`): Promise<unknown>;
  sign(digest: `0x${string}`): Promise<`0x${string}`>;
  /** This attestor's address. It acts only for policies that named it. */
  self: `0x${string}`;
  /**
   * Chain time, not wall clock. The escrow rejects an attestation whose deadline
   * has passed by comparing against block.timestamp, so a daemon signing against
   * its own clock produces expired signatures wherever the two drift: a node with
   * a skewed clock, a chain that manipulates time, or simply a slow block.
   */
  nowSeconds(): Promise<number> | number;
  log?: (line: string) => void;
}

export interface AttestorOptions {
  /** How long a signed attestation stays usable. */
  deadlineSeconds?: number;
}

export interface Skipped {
  paymentId: bigint;
  reason: string;
}

export interface SweepSummary {
  seen: number;
  attested: { paymentId: bigint; attValue: number; txHash: `0x${string}` }[];
  skipped: Skipped[];
}

const ESCROW_STATUS_DISPUTED = 2;

/**
 * One pass over the open disputes. Returns what it did rather than throwing, so a
 * single malformed dispute cannot stop the rest from being attested.
 *
 * Everything it declines to attest is recorded with a reason. Declining is a real
 * outcome, not an error: an unattested dispute resolves to the policy default after
 * resolveDelay, which is the correct result when the log cannot be verified.
 */
export async function sweepOnce(deps: AttestorDeps, options: AttestorOptions = {}): Promise<SweepSummary> {
  const { chain, log = () => {} } = deps;
  const deadlineSeconds = options.deadlineSeconds ?? 3600;

  const summary: SweepSummary = { seen: 0, attested: [], skipped: [] };

  let ids: bigint[];
  try {
    ids = await chain.recentDisputes();
  } catch (error) {
    log(`could not read disputes: ${(error as Error).message}`);
    return summary;
  }

  for (const paymentId of ids) {
    summary.seen++;
    try {
      const skip = await attestOne(deps, paymentId, deadlineSeconds, summary);
      if (skip) {
        summary.skipped.push({ paymentId, reason: skip });
        log(`payment ${paymentId}: ${skip}`);
      }
    } catch (error) {
      // One dispute failing must not take the sweep with it.
      const reason = `error: ${(error as Error).message}`;
      summary.skipped.push({ paymentId, reason });
      log(`payment ${paymentId}: ${reason}`);
    }
  }

  return summary;
}

async function attestOne(
  deps: AttestorDeps, paymentId: bigint, deadlineSeconds: number, summary: SweepSummary,
): Promise<string | null> {
  const { chain, log = () => {} } = deps;

  const payment = await chain.getPayment(paymentId);
  if (!payment) return "no such payment";
  if (payment.status !== ESCROW_STATUS_DISPUTED) return `not disputed (status ${payment.status})`;
  // Idempotence. An attestation is one-shot on chain, so a second submission would
  // simply waste gas.
  if (payment.attType !== 0) return "already attested";

  // Acting for a policy that named someone else would be rejected on chain anyway,
  // but checking first keeps the daemon honest about what it is responsible for.
  const named = await chain.attestorFor(payment.policyId);
  if (named.toLowerCase() !== deps.self.toLowerCase()) return `policy ${payment.policyId} names a different attestor`;

  const sessionId = await chain.orderRef(paymentId);
  if (!sessionId) return "could not recover the session this payment was opened for";

  let published: unknown;
  try {
    published = await deps.fetchSession(sessionId);
  } catch (error) {
    // The buyer has not published, or the host is down. Staying silent is the right
    // move: the dispute resolves to the default rather than to a number nobody can
    // check.
    return `published session unavailable: ${(error as Error).message}`;
  }

  const review: SessionReview = reviewSession(published, payment.evidenceRoot);
  if (!review.attestable) return `refusing to attest: ${review.reason}`;

  const deadline = BigInt((await deps.nowSeconds()) + deadlineSeconds);
  const digest = await chain.attestationDigest(paymentId, review.attType, review.attValue, deadline);
  const signature = await deps.sign(digest);
  const txHash = await chain.submitAttestation(paymentId, review.attType, review.attValue, deadline, signature);

  log(`payment ${paymentId}: ${review.failed}/${review.total} failed, attested severity ${review.attValue}`);
  summary.attested.push({ paymentId, attValue: review.attValue, txHash });
  return null;
}

/**
 * Sweeps on an interval until the signal aborts. Deliberately a poll rather than a
 * log subscription: the daemon has to survive restarts and missed blocks, and
 * re-reading recent disputes is idempotent by the checks above.
 */
export async function runDaemon(
  deps: AttestorDeps,
  options: AttestorOptions & { intervalMs?: number; signal?: AbortSignal } = {},
): Promise<void> {
  const intervalMs = options.intervalMs ?? 15_000;
  const { log = () => {} } = deps;

  while (!options.signal?.aborted) {
    const summary = await sweepOnce(deps, options);
    if (summary.seen > 0) {
      log(`swept ${summary.seen} disputes, attested ${summary.attested.length}, skipped ${summary.skipped.length}`);
    }
    if (options.signal?.aborted) break;
    await new Promise((resolve) => {
      const timer = setTimeout(resolve, intervalMs);
      options.signal?.addEventListener("abort", () => { clearTimeout(timer); resolve(undefined); }, { once: true });
    });
  }
}
