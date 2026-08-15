// The recourse-escrow scheme payload, docs/agent-settlement.md sections 2 and A5.
//
// Two modes, because Arc makes both reasonable. USDC is the gas token, so an agent
// holding USDC can submit its own payment and needs no relayer; but an agent funded
// only in a token it cannot pay gas with, or one behind a facilitator, signs
// instead and lets someone else submit.
//
//   settled        the buyer already called pay() and presents the payment id
//   authorization  the buyer signs EIP-3009 and the server calls payWithAuthorization
//
// The authorization mode carries the same field names as the standard `exact`
// scheme so an implementer reading both sees one shape, with two differences that
// matter: `to` is the escrow rather than the merchant, and the nonce is not free.

import { encodeAbiParameters, keccak256 } from "viem";
import { X402Error } from "./types";

export interface EscrowAuthorization {
  from: `0x${string}`;
  /** The escrow. Funds are held, not delivered to the merchant. */
  to: `0x${string}`;
  /** Atomic units, decimal string, matching PaymentRequirements.amount. */
  value: string;
  validAfter: string;
  validBefore: string;
  nonce: `0x${string}`;
}

export type RecourseEscrowPayload =
  | { mode: "settled"; paymentId: string; sessionId: `0x${string}` }
  | { mode: "authorization"; signature: `0x${string}`; authorization: EscrowAuthorization; sessionId: `0x${string}` };

/**
 * Mirrors RecourseEscrow.authorizationNonce. The nonce commits to the policy and
 * the order, so an authorization lifted from the mempool cannot be pointed at a
 * different policy; EIP-3009 then stops it being replayed against the same one.
 *
 * A buyer must derive it this way rather than choosing randomly, or the escrow
 * rejects the payment with BadNonce.
 */
export function authorizationNonce(policyId: bigint, orderRef: `0x${string}`, from: `0x${string}`): `0x${string}` {
  return keccak256(
    encodeAbiParameters(
      [{ type: "uint256" }, { type: "bytes32" }, { type: "address" }],
      [policyId, orderRef, from.toLowerCase() as `0x${string}`],
    ),
  );
}

const HEX_20 = /^0x[0-9a-fA-F]{40}$/;
const HEX_32 = /^0x[0-9a-fA-F]{64}$/;
const DECIMAL = /^[0-9]+$/;

export function parseRecourseEscrowPayload(payload: Record<string, unknown>): RecourseEscrowPayload {
  const sessionId = payload.sessionId;
  if (typeof sessionId !== "string" || !HEX_32.test(sessionId)) {
    throw new X402Error("payload.sessionId must be a 32-byte hex string.", "invalid_payload");
  }

  if (payload.mode === "settled") {
    const paymentId = payload.paymentId;
    if (typeof paymentId !== "string" || !DECIMAL.test(paymentId)) {
      throw new X402Error("payload.paymentId must be a decimal string.", "invalid_payload");
    }
    return { mode: "settled", paymentId, sessionId: sessionId as `0x${string}` };
  }

  if (payload.mode === "authorization") {
    const signature = payload.signature;
    if (typeof signature !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(signature)) {
      throw new X402Error("payload.signature must be a 65-byte hex string.", "invalid_payload");
    }
    const auth = payload.authorization as Record<string, unknown> | undefined;
    if (!auth || typeof auth !== "object") {
      throw new X402Error("payload.authorization is missing.", "invalid_payload");
    }
    const field = (key: string, pattern: RegExp): string => {
      const value = auth[key];
      if (typeof value !== "string" || !pattern.test(value)) {
        throw new X402Error(`payload.authorization.${key} is missing or malformed.`, "invalid_payload");
      }
      return value;
    };
    return {
      mode: "authorization",
      signature: signature as `0x${string}`,
      sessionId: sessionId as `0x${string}`,
      authorization: {
        from: field("from", HEX_20) as `0x${string}`,
        to: field("to", HEX_20) as `0x${string}`,
        value: field("value", DECIMAL),
        validAfter: field("validAfter", DECIMAL),
        validBefore: field("validBefore", DECIMAL),
        nonce: field("nonce", HEX_32) as `0x${string}`,
      },
    };
  }

  throw new X402Error(`Unknown recourse-escrow payload mode ${String(payload.mode)}.`, "invalid_payload");
}
