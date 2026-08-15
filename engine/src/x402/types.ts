// x402 v2 core types, from coinbase/x402 specs/x402-specification-v2.md and
// specs/transports-v2/http.md. Field names are the wire format and must not be
// renamed for readability.
//
// These are transport and scheme independent. The Recourse-specific parts are the
// scheme in scheme.ts and the extension in extension.ts, which is how x402 is meant
// to be extended: a client that knows nothing about Recourse still parses the
// payment and simply forfeits the protection.

export const X402_VERSION = 2;

/** CAIP-2. Arc testnet, the only network this ships against today. */
export const ARC_TESTNET_CAIP2 = "eip155:5042002";

/** Scheme identifier. Not "exact": that settles straight to payTo and cannot escrow. */
export const RECOURSE_SCHEME = "recourse-escrow";

export interface ResourceInfo {
  url: string;
  description?: string;
  mimeType?: string;
}

export interface PaymentRequirements {
  scheme: string;
  /** CAIP-2, e.g. "eip155:5042002". */
  network: string;
  /** Atomic token units as a decimal string. USDC is 6 decimals on Arc. */
  amount: string;
  /** Token contract address, or an ISO 4217 code for fiat rails. */
  asset: string;
  /** For this scheme the escrow, not the merchant. */
  payTo: string;
  maxTimeoutSeconds: number;
  extra?: Record<string, unknown>;
}

/**
 * One extension entry. The server advertises `info` alongside the JSON Schema that
 * describes it, and the client echoes both back.
 */
export interface Extension {
  info: Record<string, unknown>;
  schema: Record<string, unknown>;
}

export type Extensions = Record<string, Extension>;

/** Sent by the resource server with a 402, base64 in the PAYMENT-REQUIRED header. */
export interface PaymentRequired {
  x402Version: number;
  error?: string;
  resource: ResourceInfo;
  accepts: PaymentRequirements[];
  extensions?: Extensions;
}

/** Sent by the client, base64 in the PAYMENT-SIGNATURE header. */
export interface PaymentPayload {
  x402Version: number;
  resource?: ResourceInfo;
  /** The PaymentRequirements entry the client chose out of `accepts`. */
  accepted: PaymentRequirements;
  /** Scheme specific. See scheme.ts for recourse-escrow. */
  payload: Record<string, unknown>;
  extensions?: Extensions;
}

/** Returned by the server, base64 in the PAYMENT-RESPONSE header. */
export interface SettlementResponse {
  success: boolean;
  transaction: string;
  network: string;
  payer: string;
  errorReason?: string;
}

export class X402Error extends Error {
  constructor(
    message: string,
    readonly reason: string,
  ) {
    super(message);
    this.name = "X402Error";
  }
}
