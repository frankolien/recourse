import { describe, it, expect } from "vitest";
import { keccak256, encodeAbiParameters } from "viem";
import {
  ARC_TESTNET_CAIP2,
  RECOURSE_SCHEME,
  X402Error,
  X402_VERSION,
  assertExtensionsEchoed,
  assessProtection,
  authorizationMessage,
  authorizationNonce,
  buildPayment,
  buildPaymentHeader,
  decodePaymentPayload,
  decodePaymentRequired,
  echoExtensions,
  encodePaymentRequired,
  parseQuote,
  parseRecourseEscrowPayload,
  quote,
  quoteHeader,
  readRecourseExtension,
  verify,
  verifyTerms,
  EscrowStatus,
  type EscrowPayment,
  type EscrowReader,
  type QuoteOptions,
} from "../src/x402";
import { agentServicePolicy } from "../src/agent";
import { policyHash } from "../src/hash";
import { AgentClaimType, AgentEvidence } from "../src/types";
import type { Policy } from "../src/types";

const MERCHANT = "0x00000000000000000000000000000000000000A2" as const;
const ATTESTOR = "0x00000000000000000000000000000000000000A3" as const;
const BUYER = "0x00000000000000000000000000000000000000B1" as const;
const ESCROW = "0x61Fd99789B28582882a3369E2024AeaE5b5D2DC0" as const;
const USDC = "0x3600000000000000000000000000000000000000" as const;
const SESSION = `0x${"5e".repeat(32)}` as const;

const POLICY: Policy = agentServicePolicy({ merchant: MERCHANT, disputeWindowSeconds: 3600 });

const AGREEMENT = keccak256(
  encodeAbiParameters([{ type: "bytes32" }, { type: "address" }], [policyHash(POLICY), ATTESTOR]),
);

const QUOTE_OPTIONS: QuoteOptions = {
  resource: { url: "https://api.example.com/infer", mimeType: "application/json" },
  amount: 5_000_000n,
  asset: USDC,
  escrow: ESCROW,
  terms: {
    policyId: "42",
    policyHash: policyHash(POLICY),
    agreementHash: AGREEMENT,
    merchant: MERCHANT,
    attestor: ATTESTOR,
    escrow: ESCROW,
    disputeWindow: 3600,
    engineVersion: "1",
  },
};

function reader(over: Partial<EscrowPayment> = {}, orderRef: `0x${string}` | null = SESSION): EscrowReader {
  const payment: EscrowPayment = {
    buyer: BUYER,
    merchant: MERCHANT,
    policyId: 42n,
    amount: 5_000_000n,
    paidAt: 1_700_000_000n,
    status: EscrowStatus.Paid,
    ...over,
  };
  return {
    getPayment: async () => payment,
    getOrderRef: async () => orderRef,
  };
}

const settled = { mode: "settled", paymentId: "7", sessionId: SESSION } as const;

describe("x402 v2 wire format", () => {
  it("quotes the escrow as payTo, not the merchant", () => {
    const pr = quote(QUOTE_OPTIONS);
    expect(pr.x402Version).toBe(X402_VERSION);
    expect(pr.accepts).toHaveLength(1);
    expect(pr.accepts[0]!.scheme).toBe(RECOURSE_SCHEME);
    expect(pr.accepts[0]!.network).toBe(ARC_TESTNET_CAIP2);
    // Funds are held under the policy rather than delivered on payment. This is the
    // entire difference from the standard `exact` scheme.
    expect(pr.accepts[0]!.payTo).toBe(ESCROW);
    expect(pr.accepts[0]!.payTo).not.toBe(MERCHANT);
    expect(pr.accepts[0]!.amount).toBe("5000000");
    expect(pr.accepts[0]!.extra).toEqual({ name: "USDC", version: "2" });
  });

  it("round trips through base64 headers", () => {
    const header = quoteHeader(QUOTE_OPTIONS);
    expect(header).toBe(Buffer.from(JSON.stringify(quote(QUOTE_OPTIONS)), "utf8").toString("base64"));
    expect(decodePaymentRequired(header)).toEqual(quote(QUOTE_OPTIONS));
  });

  it("refuses a payload from a different protocol version", () => {
    const wrong = { ...quote(QUOTE_OPTIONS), x402Version: 1 };
    expect(() => decodePaymentRequired(encodePaymentRequired(wrong))).toThrow(X402Error);
  });

  it("rejects malformed base64 and JSON rather than guessing", () => {
    expect(() => decodePaymentRequired("not base64 at all !!")).toThrow(X402Error);
    expect(() => decodePaymentPayload(Buffer.from("{", "utf8").toString("base64"))).toThrow(X402Error);
  });
});

describe("recourse/v1 extension", () => {
  it("is absent rather than invalid for an unprotected payment", () => {
    expect(readRecourseExtension(undefined)).toBeNull();
    expect(readRecourseExtension({})).toBeNull();
  });

  it("throws when present but malformed, so terms are never inferred", () => {
    expect(() => readRecourseExtension({ "recourse/v1": { info: { policyId: "x" }, schema: {} } })).toThrow(X402Error);
  });

  // The spec allows a client to append info but never to delete or overwrite what
  // the server sent.
  it("cannot be overwritten by client additions", () => {
    const sent = quote(QUOTE_OPTIONS).extensions!;
    const echoed = echoExtensions(sent, {
      "recourse/v1": { info: { attestor: "0xdeadbeef", extra: "mine" }, schema: {} },
    });
    expect(echoed["recourse/v1"]!.info.attestor).toBe(ATTESTOR);
    expect(echoed["recourse/v1"]!.info.extra).toBe("mine");
    expect(() => assertExtensionsEchoed(sent, echoed)).not.toThrow();
  });

  it("is caught server side when a client drops or alters a term", () => {
    const sent = quote(QUOTE_OPTIONS).extensions!;
    expect(() => assertExtensionsEchoed(sent, {})).toThrow(X402Error);
    expect(() =>
      assertExtensionsEchoed(sent, {
        "recourse/v1": { info: { ...sent["recourse/v1"]!.info, disputeWindow: 999999 }, schema: {} },
      }),
    ).toThrow(X402Error);
  });
});

describe("authorization nonce binding", () => {
  // Pinned against the Solidity escrow's authorizationNonce for the same inputs.
  // A divergence here is invisible locally and rejects every relayed payment on
  // chain with BadNonce, so both suites assert the same literal.
  it("matches the value RecourseEscrow derives on chain", () => {
    expect(authorizationNonce(42n, SESSION, BUYER)).toBe(
      "0xc0add9bcb03087e86c24fe2da04f94753ef5485be83c6244cee0c7ccb6451c5a",
    );
  });

  it("matches the escrow's authorizationNonce formula", () => {
    const expected = keccak256(
      encodeAbiParameters(
        [{ type: "uint256" }, { type: "bytes32" }, { type: "address" }],
        [42n, SESSION, BUYER.toLowerCase() as `0x${string}`],
      ),
    );
    expect(authorizationNonce(42n, SESSION, BUYER)).toBe(expected);
  });

  it("changes with the policy and with the session, which is what stops redirection", () => {
    const base = authorizationNonce(42n, SESSION, BUYER);
    expect(authorizationNonce(43n, SESSION, BUYER)).not.toBe(base);
    expect(authorizationNonce(42n, `0x${"11".repeat(32)}`, BUYER)).not.toBe(base);
  });

  it("builds an authorization that pays the escrow with a derived nonce", () => {
    const auth = authorizationMessage({
      policyId: 42n,
      sessionId: SESSION,
      from: BUYER,
      escrow: ESCROW,
      amount: 5_000_000n,
      validBefore: 1_800_000_000n,
    });
    expect(auth.to).toBe(ESCROW);
    expect(auth.value).toBe("5000000");
    expect(auth.nonce).toBe(authorizationNonce(42n, SESSION, BUYER));
  });
});

describe("payload parsing", () => {
  it("accepts both modes and rejects anything else", () => {
    expect(parseRecourseEscrowPayload({ ...settled })).toMatchObject({ mode: "settled", paymentId: "7" });
    expect(() => parseRecourseEscrowPayload({ mode: "wat", sessionId: SESSION })).toThrow(X402Error);
    expect(() => parseRecourseEscrowPayload({ mode: "settled", paymentId: "7" })).toThrow(X402Error);
    expect(() => parseRecourseEscrowPayload({ mode: "settled", paymentId: "0x7", sessionId: SESSION })).toThrow(X402Error);
  });
});

describe("buyer assessment", () => {
  const assessment = assessProtection(POLICY);

  it("reports the unmeasurable outcome as the worst case", () => {
    expect(assessment.worstCaseRefundBps).toBe(5_000);
    expect(assessment.disputeWindow).toBe(3600);
  });

  it("reports the best refund per claim and what earning it costs", () => {
    const partial = assessment.byClaim.find((c) => c.claimType === AgentClaimType.PartialFailure)!;
    expect(partial.refundBps).toBe(10_000);
    expect(partial.needsAttestation).toBe(true);
    expect(partial.requiredEvidenceMask).toBe(AgentEvidence.CallLogRoot);

    const schema = assessment.byClaim.find((c) => c.claimType === AgentClaimType.SchemaViolation)!;
    expect(schema.needsAttestation).toBe(false);
    expect(schema.requiredEvidenceMask).toBe(AgentEvidence.CallLogRoot | AgentEvidence.SchemaFailure);
  });

  it("accepts terms that match the chain", async () => {
    const check = await verifyTerms(QUOTE_OPTIONS.terms, {
      agreementHash: async () => AGREEMENT,
      getPolicy: async () => POLICY,
    });
    expect(check.ok).toBe(true);
    expect(check.problems).toEqual([]);
    expect(check.assessment?.worstCaseRefundBps).toBe(5_000);
  });

  it("refuses a seller that advertises terms the chain does not agree with", async () => {
    const check = await verifyTerms(QUOTE_OPTIONS.terms, {
      agreementHash: async () => `0x${"99".repeat(32)}`,
      getPolicy: async () => POLICY,
    });
    expect(check.ok).toBe(false);
    expect(check.problems).toContain("advertised agreementHash does not match the escrow");
    expect(check.assessment).toBeNull();
  });

  // The precondition the entire dispute path rests on, checked before paying rather
  // than discovered during a dispute.
  it("refuses a merchant that is its own attestor", async () => {
    const check = await verifyTerms(
      { ...QUOTE_OPTIONS.terms, attestor: MERCHANT },
      { agreementHash: async () => QUOTE_OPTIONS.terms.agreementHash, getPolicy: async () => POLICY },
    );
    expect(check.ok).toBe(false);
    expect(check.problems).toContain("attestor is the merchant, so a dispute cannot be settled honestly");
  });
});

describe("seller verification", () => {
  const quoted = quote(QUOTE_OPTIONS);
  const good = buildPaymentHeader(parseQuote(quoteHeader(QUOTE_OPTIONS)), settled);

  it("accepts a payment that matches the quote and the chain", async () => {
    const result = await verify(good, quoted, reader());
    expect(result).toMatchObject({ ok: true, payer: BUYER, paymentId: 7n });
  });

  it("rejects a payment opened for a different session", async () => {
    const result = await verify(good, quoted, reader({}, `0x${"ab".repeat(32)}`));
    expect(result).toMatchObject({ ok: false, reason: "session_mismatch" });
  });

  it("rejects a payment to another merchant, policy, or amount", async () => {
    expect(await verify(good, quoted, reader({ merchant: BUYER }))).toMatchObject({ ok: false, reason: "wrong_merchant" });
    expect(await verify(good, quoted, reader({ policyId: 99n }))).toMatchObject({ ok: false, reason: "wrong_policy" });
    expect(await verify(good, quoted, reader({ amount: 1n }))).toMatchObject({ ok: false, reason: "insufficient_amount" });
  });

  it("rejects a payment that is not open", async () => {
    expect(await verify(good, quoted, reader({ status: EscrowStatus.Settled }))).toMatchObject({
      ok: false,
      reason: "payment_not_open",
    });
    expect(await verify(good, quoted, reader({ status: EscrowStatus.None }))).toMatchObject({
      ok: false,
      reason: "unknown_payment",
    });
  });

  it("rejects a buyer that quietly changed the terms it was offered", async () => {
    const q = parseQuote(quoteHeader(QUOTE_OPTIONS));
    const tampered = buildPayment(q, settled);
    tampered.extensions!["recourse/v1"]!.info.disputeWindow = 999_999;
    const header = Buffer.from(JSON.stringify(tampered), "utf8").toString("base64");
    expect(await verify(header, quoted, reader())).toMatchObject({ ok: false, reason: "extension_not_echoed" });
  });

  it("rejects a payload claiming a scheme or asset that was never offered", async () => {
    const q = parseQuote(quoteHeader(QUOTE_OPTIONS));
    const swapped = buildPayment(q, settled);
    swapped.accepted = { ...swapped.accepted, asset: BUYER };
    const header = Buffer.from(JSON.stringify(swapped), "utf8").toString("base64");
    expect(await verify(header, quoted, reader())).toMatchObject({ ok: false, reason: "requirements_mismatch" });
  });

  it("returns settle for an authorization, which cannot be verified before submission", async () => {
    const q = parseQuote(quoteHeader(QUOTE_OPTIONS));
    const auth = authorizationMessage({
      policyId: 42n,
      sessionId: SESSION,
      from: BUYER,
      escrow: ESCROW,
      amount: 5_000_000n,
      validBefore: BigInt(Math.floor(Date.now() / 1000) + 3600),
    });
    const header = buildPaymentHeader(q, {
      mode: "authorization",
      signature: `0x${"11".repeat(65)}`,
      authorization: auth,
      sessionId: SESSION,
    });
    expect(await verify(header, quoted, reader())).toMatchObject({ ok: "settle" });
  });

  it("rejects an authorization whose nonce is not bound to this policy and session", async () => {
    const q = parseQuote(quoteHeader(QUOTE_OPTIONS));
    const auth = authorizationMessage({
      policyId: 43n, // a policy the buyer was never quoted
      sessionId: SESSION,
      from: BUYER,
      escrow: ESCROW,
      amount: 5_000_000n,
      validBefore: BigInt(Math.floor(Date.now() / 1000) + 3600),
    });
    const header = buildPaymentHeader(q, {
      mode: "authorization",
      signature: `0x${"11".repeat(65)}`,
      authorization: auth,
      sessionId: SESSION,
    });
    expect(await verify(header, quoted, reader())).toMatchObject({ ok: false, reason: "bad_nonce" });
  });
});

// Both halves against each other, in the order docs/agent-settlement.md A5 lays out.
describe("end to end handshake", () => {
  it("carries a buyer from 402 to a served request", async () => {
    // 2. seller answers with terms attached
    const header = quoteHeader(QUOTE_OPTIONS);

    // 3. buyer reads the offer and checks it against chain state
    const q = parseQuote(header);
    expect(q.terms).not.toBeNull();
    const check = await verifyTerms(q.terms!, {
      agreementHash: async () => AGREEMENT,
      getPolicy: async () => POLICY,
    });
    expect(check.ok).toBe(true);

    // 4. buyer sees what protection it is actually buying before spending anything
    expect(check.assessment!.worstCaseRefundBps).toBe(5_000);
    expect(check.assessment!.byClaim.some((c) => c.refundBps === 10_000)).toBe(true);

    // 5 and 6. buyer pays and presents the payment
    const presented = buildPaymentHeader(q, settled);

    // 7. seller verifies before serving
    const result = await verify(presented, quote(QUOTE_OPTIONS), reader());
    expect(result).toMatchObject({ ok: true, payer: BUYER });
  });

  it("lets an x402 client that never heard of Recourse still pay correctly", () => {
    const pr = decodePaymentRequired(quoteHeader(QUOTE_OPTIONS));
    // Such a client reads accepts[0] and ignores extensions entirely. It pays the
    // right amount to the right address and simply forfeits the dispute path.
    expect(pr.accepts[0]!.amount).toBe("5000000");
    expect(pr.accepts[0]!.asset).toBe(USDC);
    expect(pr.accepts[0]!.payTo).toBe(ESCROW);
  });
});
