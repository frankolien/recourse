// Buyer side. Reads a 402, works out what protection the advertised policy actually
// gives, and builds the payment.
//
// The assessment step is the reason this exists at all. An agent should not decide
// to pay because a server said the word escrow; it should read the rules, run them
// through the same engine that will settle them, and see the numbers first. That is
// free and offline: compute() is the mirror of the Solidity engine, pinned to it by
// packages/vectors.

import { compute } from "../engine";
import type { Policy, VerdictInput } from "../types";
import { echoExtensions, readRecourseExtension } from "./extension";
import type { RecourseExtensionInfo } from "./extension";
import { decodePaymentRequired, encodePaymentPayload } from "./headers";
import { authorizationNonce } from "./scheme";
import type { EscrowAuthorization, RecourseEscrowPayload } from "./scheme";
import { ARC_TESTNET_CAIP2, RECOURSE_SCHEME, X402Error, X402_VERSION } from "./types";
import type { PaymentPayload, PaymentRequired, PaymentRequirements } from "./types";

export interface Quote {
  paymentRequired: PaymentRequired;
  requirements: PaymentRequirements;
  /** Null when the server offered no protection, which is a valid plain payment. */
  terms: RecourseExtensionInfo | null;
}

/**
 * Picks the first requirement this client can actually satisfy. Throws when none
 * match, rather than paying under a scheme it cannot dispute.
 */
export function parseQuote(header: string, network: string = ARC_TESTNET_CAIP2): Quote {
  const paymentRequired = decodePaymentRequired(header);
  const requirements = paymentRequired.accepts.find(
    (entry) => entry.scheme === RECOURSE_SCHEME && entry.network === network,
  );
  if (!requirements) {
    throw new X402Error(`No ${RECOURSE_SCHEME} offer on ${network}.`, "no_acceptable_scheme");
  }
  return { paymentRequired, requirements, terms: readRecourseExtension(paymentRequired.extensions) };
}

export interface ClaimOutlook {
  claimType: number;
  refundBps: number;
  requiredEvidenceMask: number;
  needsAttestation: boolean;
  attExpected: number;
  claimWindow: number;
}

export interface ProtectionAssessment {
  /** What a dispute returns when nothing matches: no evidence, no attestation. */
  worstCaseRefundBps: number;
  /** Best refund available per claim type, with what it costs to earn it. */
  byClaim: ClaimOutlook[];
  /** Seconds in which any dispute must be filed. */
  disputeWindow: number;
}

const UNMATCHABLE_CLAIM = 255;

export function assessProtection(policy: Policy): ProtectionAssessment {
  // A claim type no rule declares falls through to defaultRefundBps, which is
  // exactly the "we could not measure anything" outcome.
  const probe: VerdictInput = {
    claimType: UNMATCHABLE_CLAIM,
    evidenceMask: 0,
    attType: 0,
    attValue: 0,
    paidAt: 0n,
    filedAt: 0n,
  };

  const byClaim = new Map<number, ClaimOutlook>();
  for (const rule of policy.rules) {
    const current = byClaim.get(rule.claimType);
    if (current && current.refundBps >= rule.refundBps) continue;
    byClaim.set(rule.claimType, {
      claimType: rule.claimType,
      refundBps: rule.refundBps,
      requiredEvidenceMask: rule.requiredEvidenceMask,
      needsAttestation: rule.attType !== 0,
      attExpected: rule.attExpected,
      claimWindow: rule.claimWindow,
    });
  }

  return {
    worstCaseRefundBps: compute(policy, probe).refundBps,
    byClaim: [...byClaim.values()].sort((a, b) => a.claimType - b.claimType),
    disputeWindow: policy.disputeWindow,
  };
}

export interface AgreementReader {
  agreementHash(policyId: bigint): Promise<`0x${string}`>;
  getPolicy(policyId: bigint): Promise<Policy>;
}

export interface TermsCheck {
  ok: boolean;
  problems: string[];
  policy: Policy | null;
  assessment: ProtectionAssessment | null;
}

/**
 * Everything a buyer should confirm before paying. The advertised terms are just a
 * claim by the seller; each one is checked against chain state, and the agreement
 * hash is what ties the two together.
 */
export async function verifyTerms(terms: RecourseExtensionInfo, reader: AgreementReader): Promise<TermsCheck> {
  const problems: string[] = [];
  const policyId = BigInt(terms.policyId);
  const policy = await reader.getPolicy(policyId);

  const onchain = await reader.agreementHash(policyId);
  if (onchain.toLowerCase() !== terms.agreementHash.toLowerCase()) {
    problems.push("advertised agreementHash does not match the escrow");
  }
  if (policy.merchant.toLowerCase() !== terms.merchant.toLowerCase()) {
    problems.push("advertised merchant is not the policy merchant");
  }
  // The precondition the whole dispute path rests on. A merchant that can attest
  // against its own dispute defeats the engine whichever way the default points.
  if (terms.attestor.toLowerCase() === terms.merchant.toLowerCase()) {
    problems.push("attestor is the merchant, so a dispute cannot be settled honestly");
  }
  if (policy.disputeWindow !== terms.disputeWindow) {
    problems.push("advertised disputeWindow does not match the policy");
  }

  return {
    ok: problems.length === 0,
    problems,
    policy,
    assessment: problems.length === 0 ? assessProtection(policy) : null,
  };
}

/** The EIP-712 message a payer signs for the authorization mode. */
export function authorizationMessage(args: {
  policyId: bigint;
  sessionId: `0x${string}`;
  from: `0x${string}`;
  escrow: `0x${string}`;
  amount: bigint;
  validAfter?: bigint;
  validBefore: bigint;
}): EscrowAuthorization {
  return {
    from: args.from,
    to: args.escrow,
    value: args.amount.toString(),
    validAfter: (args.validAfter ?? 0n).toString(),
    validBefore: args.validBefore.toString(),
    // Derived, never random: the escrow recomputes it and rejects a mismatch.
    nonce: authorizationNonce(args.policyId, args.sessionId, args.from),
  };
}

export function buildPayment(quote: Quote, payload: RecourseEscrowPayload): PaymentPayload {
  return {
    x402Version: X402_VERSION,
    resource: quote.paymentRequired.resource,
    accepted: quote.requirements,
    payload: payload as unknown as Record<string, unknown>,
    // Echoed rather than rebuilt, so the server can confirm the buyer agreed to the
    // terms it actually advertised.
    extensions: echoExtensions(quote.paymentRequired.extensions),
  };
}

export const buildPaymentHeader = (quote: Quote, payload: RecourseEscrowPayload): string =>
  encodePaymentPayload(buildPayment(quote, payload));
