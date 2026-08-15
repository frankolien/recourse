// HTTP transport binding, from specs/transports-v2/http.md. All three headers carry
// base64 encoded JSON of the schemas in types.ts.
//
// v1 used X-PAYMENT. These are the v2 names and are what this ships against.

import { X402Error, X402_VERSION } from "./types";
import type { PaymentPayload, PaymentRequired, SettlementResponse } from "./types";

export const PAYMENT_REQUIRED_HEADER = "PAYMENT-REQUIRED";
export const PAYMENT_SIGNATURE_HEADER = "PAYMENT-SIGNATURE";
export const PAYMENT_RESPONSE_HEADER = "PAYMENT-RESPONSE";

// Base64 rather than base64url: the spec's own example decodes as standard base64,
// and these travel in header values where + and / are legal.
function encode(value: unknown): string {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64");
}

function decode<T>(header: string, label: string): T {
  let text: string;
  try {
    text = Buffer.from(header, "base64").toString("utf8");
  } catch {
    throw new X402Error(`${label} is not valid base64.`, "invalid_encoding");
  }
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new X402Error(`${label} is not valid JSON.`, "invalid_encoding");
  }
}

export const encodePaymentRequired = (value: PaymentRequired): string => encode(value);
export const encodePaymentPayload = (value: PaymentPayload): string => encode(value);
export const encodeSettlementResponse = (value: SettlementResponse): string => encode(value);

export function decodePaymentRequired(header: string): PaymentRequired {
  const value = decode<PaymentRequired>(header, PAYMENT_REQUIRED_HEADER);
  requireVersion(value.x402Version, PAYMENT_REQUIRED_HEADER);
  if (!value.resource?.url) throw new X402Error("PaymentRequired is missing resource.url.", "invalid_request");
  if (!Array.isArray(value.accepts) || value.accepts.length === 0) {
    throw new X402Error("PaymentRequired lists no acceptable payment methods.", "invalid_request");
  }
  return value;
}

export function decodePaymentPayload(header: string): PaymentPayload {
  const value = decode<PaymentPayload>(header, PAYMENT_SIGNATURE_HEADER);
  requireVersion(value.x402Version, PAYMENT_SIGNATURE_HEADER);
  if (!value.accepted) throw new X402Error("PaymentPayload is missing `accepted`.", "invalid_request");
  if (!value.payload) throw new X402Error("PaymentPayload is missing `payload`.", "invalid_request");
  return value;
}

export const decodeSettlementResponse = (header: string): SettlementResponse =>
  decode<SettlementResponse>(header, PAYMENT_RESPONSE_HEADER);

// Rejected rather than coerced: a version mismatch means the other side is reading
// different field semantics, and guessing which is worse than failing.
function requireVersion(version: unknown, label: string): void {
  if (version !== X402_VERSION) {
    throw new X402Error(`${label} declares x402Version ${String(version)}, expected ${X402_VERSION}.`, "invalid_version");
  }
}

/** Case insensitive lookup, since HTTP header names are not case sensitive. */
export function readHeader(headers: Headers | Record<string, string | undefined>, name: string): string | undefined {
  if (typeof (headers as Headers).get === "function") {
    return (headers as Headers).get(name) ?? undefined;
  }
  const lower = name.toLowerCase();
  for (const [key, value] of Object.entries(headers as Record<string, string | undefined>)) {
    if (key.toLowerCase() === lower) return value ?? undefined;
  }
  return undefined;
}
