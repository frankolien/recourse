// Seller side. Quotes a price with its refund terms attached, and verifies what a
// buyer presents before serving anything.
//
// Framework agnostic on purpose: these are functions over header strings, so the
// same code sits behind Next.js, Hono, Express or a raw fetch handler.

import { assertExtensionsEchoed, buildRecourseExtension } from "./extension";
import type { RecourseExtensionInfo } from "./extension";
import { decodePaymentPayload, encodePaymentRequired } from "./headers";
import { authorizationNonce, parseRecourseEscrowPayload } from "./scheme";
import type { RecourseEscrowPayload } from "./scheme";
import { ARC_TESTNET_CAIP2, RECOURSE_SCHEME, X402Error, X402_VERSION } from "./types";
import type { PaymentRequired, PaymentRequirements, ResourceInfo } from "./types";

/** Mirrors RecourseEscrow.Status. */
export const EscrowStatus = { None: 0, Paid: 1, Disputed: 2, Settled: 3 } as const;

export interface EscrowPayment {
  buyer: `0x${string}`;
  merchant: `0x${string}`;
  policyId: bigint;
  amount: bigint;
  paidAt: bigint;
  status: number;
}

export interface EscrowReader {
  getPayment(paymentId: bigint): Promise<EscrowPayment | null>;
  /**
   * orderRef for a payment. The escrow does not store it, but paymentId is indexed
   * on the Paid event, so it is recoverable from logs. Without this a buyer could
   * present one payment against many sessions with the same merchant.
   */
  getOrderRef(paymentId: bigint): Promise<`0x${string}` | null>;
}

export interface QuoteOptions {
  resource: ResourceInfo;
  /** Atomic units. The session budget, not a per-call price. */
  amount: bigint;
  asset: `0x${string}`;
  escrow: `0x${string}`;
  terms: RecourseExtensionInfo;
  network?: string;
  maxTimeoutSeconds?: number;
  error?: string;
}

export function quote(options: QuoteOptions): PaymentRequired {
  const requirements: PaymentRequirements = {
    scheme: RECOURSE_SCHEME,
    network: options.network ?? ARC_TESTNET_CAIP2,
    amount: options.amount.toString(),
    asset: options.asset,
    // The escrow, not the merchant: funds are held under the policy rather than
    // delivered on payment. This is the whole difference from the `exact` scheme.
    payTo: options.escrow,
    maxTimeoutSeconds: options.maxTimeoutSeconds ?? 60,
    extra: { name: "USDC", version: "2" },
  };

  return {
    x402Version: X402_VERSION,
    error: options.error ?? `${PAYMENT_SIGNATURE} header is required`,
    resource: options.resource,
    accepts: [requirements],
    extensions: buildRecourseExtension(options.terms),
  };
}

const PAYMENT_SIGNATURE = "PAYMENT-SIGNATURE";

export const quoteHeader = (options: QuoteOptions): string => encodePaymentRequired(quote(options));

export type VerifyResult =
  | { ok: true; payer: `0x${string}`; paymentId: bigint; payload: RecourseEscrowPayload }
  | { ok: false; reason: string; detail: string }
  | { ok: "settle"; payload: Extract<RecourseEscrowPayload, { mode: "authorization" }> };

/**
 * Checks a presented payment against the quote that produced it. Business failures
 * come back as a result rather than an exception; only malformed input throws,
 * because that is a protocol error rather than a rejected payment.
 *
 * Returns "settle" for an authorization the server still has to submit, so the
 * caller decides whether to relay it. Verification cannot confirm what has not
 * happened yet.
 */
export async function verify(
  header: string,
  quoted: PaymentRequired,
  reader: EscrowReader,
): Promise<VerifyResult> {
  const presented = decodePaymentPayload(header);
  const required = quoted.accepts[0]!;
  const terms = quoted.extensions?.["recourse/v1"]?.info as unknown as RecourseExtensionInfo | undefined;
  if (!terms) throw new X402Error("Quote carried no recourse/v1 terms.", "invalid_request");

  const mismatch = matchRequirements(presented.accepted, required);
  if (mismatch) return { ok: false, reason: "requirements_mismatch", detail: mismatch };

  try {
    assertExtensionsEchoed(quoted.extensions, presented.extensions);
  } catch (error) {
    return { ok: false, reason: "extension_not_echoed", detail: (error as Error).message };
  }

  const payload = parseRecourseEscrowPayload(presented.payload);

  if (payload.mode === "authorization") {
    const auth = payload.authorization;
    const expectedNonce = authorizationNonce(BigInt(terms.policyId), payload.sessionId, auth.from);
    if (auth.nonce.toLowerCase() !== expectedNonce.toLowerCase()) {
      return { ok: false, reason: "bad_nonce", detail: "authorization nonce is not bound to this policy and session" };
    }
    if (auth.to.toLowerCase() !== terms.escrow.toLowerCase()) {
      return { ok: false, reason: "bad_recipient", detail: "authorization does not pay the escrow" };
    }
    if (BigInt(auth.value) < BigInt(required.amount)) {
      return { ok: false, reason: "insufficient_amount", detail: `authorized ${auth.value}, required ${required.amount}` };
    }
    if (BigInt(auth.validBefore) <= BigInt(Math.floor(Date.now() / 1000))) {
      return { ok: false, reason: "authorization_expired", detail: "validBefore is in the past" };
    }
    return { ok: "settle", payload };
  }

  const paymentId = BigInt(payload.paymentId);
  const payment = await reader.getPayment(paymentId);
  if (!payment || payment.status === EscrowStatus.None) {
    return { ok: false, reason: "unknown_payment", detail: `payment ${payload.paymentId} does not exist` };
  }
  if (payment.status !== EscrowStatus.Paid) {
    return { ok: false, reason: "payment_not_open", detail: `payment is in status ${payment.status}` };
  }
  if (payment.merchant.toLowerCase() !== terms.merchant.toLowerCase()) {
    return { ok: false, reason: "wrong_merchant", detail: "payment was made to a different merchant" };
  }
  if (payment.policyId !== BigInt(terms.policyId)) {
    return { ok: false, reason: "wrong_policy", detail: "payment is pinned to a different policy" };
  }
  if (payment.amount < BigInt(required.amount)) {
    return { ok: false, reason: "insufficient_amount", detail: `escrowed ${payment.amount}, required ${required.amount}` };
  }

  // Binds this payment to this session. Without it one payment buys unlimited
  // sessions from the same merchant.
  const orderRef = await reader.getOrderRef(paymentId);
  if (!orderRef || orderRef.toLowerCase() !== payload.sessionId.toLowerCase()) {
    return { ok: false, reason: "session_mismatch", detail: "payment was not opened for this session" };
  }

  return { ok: true, payer: payment.buyer, paymentId, payload };
}

function matchRequirements(presented: PaymentRequirements, required: PaymentRequirements): string | null {
  if (presented.scheme !== required.scheme) return `scheme ${presented.scheme} was not offered`;
  if (presented.network !== required.network) return `network ${presented.network} was not offered`;
  if (presented.asset.toLowerCase() !== required.asset.toLowerCase()) return "asset does not match the quote";
  if (presented.payTo.toLowerCase() !== required.payTo.toLowerCase()) return "payTo does not match the quote";
  if (BigInt(presented.amount) < BigInt(required.amount)) {
    return `amount ${presented.amount} is below the quoted ${required.amount}`;
  }
  return null;
}
