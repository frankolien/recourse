// The recourse/v1 x402 extension: the refund terms a buyer needs in order to know
// what protection it is getting, advertised by the server and echoed by the client.
//
// This rides in `extensions` rather than in a fork of the protocol so that an x402
// client which has never heard of Recourse still parses the payment correctly and
// simply forfeits the protection. Degraded, not broken.

import { X402Error } from "./types";
import type { Extension, Extensions } from "./types";

export const RECOURSE_EXTENSION_ID = "recourse/v1";

export interface RecourseExtensionInfo {
  /** Decimal string: policy ids are uint256 on chain. */
  policyId: string;
  /** Covers the rules. */
  policyHash: `0x${string}`;
  /** Covers the rules and the attestor. This is the value to check, not policyHash. */
  agreementHash: `0x${string}`;
  merchant: `0x${string}`;
  attestor: `0x${string}`;
  escrow: `0x${string}`;
  /** Seconds. Any dispute must be filed within this of payment. */
  disputeWindow: number;
  engineVersion: string;
}

// Advertised alongside the info so a client can validate the shape it was handed
// rather than trusting field names.
export const RECOURSE_EXTENSION_SCHEMA = {
  type: "object",
  required: ["policyId", "policyHash", "agreementHash", "merchant", "attestor", "escrow", "disputeWindow", "engineVersion"],
  additionalProperties: false,
  properties: {
    policyId: { type: "string", pattern: "^[0-9]+$" },
    policyHash: { type: "string", pattern: "^0x[0-9a-fA-F]{64}$" },
    agreementHash: { type: "string", pattern: "^0x[0-9a-fA-F]{64}$" },
    merchant: { type: "string", pattern: "^0x[0-9a-fA-F]{40}$" },
    attestor: { type: "string", pattern: "^0x[0-9a-fA-F]{40}$" },
    escrow: { type: "string", pattern: "^0x[0-9a-fA-F]{40}$" },
    disputeWindow: { type: "integer", minimum: 1 },
    engineVersion: { type: "string" },
  },
} as const;

export function buildRecourseExtension(info: RecourseExtensionInfo): Extensions {
  return {
    [RECOURSE_EXTENSION_ID]: {
      info: { ...info } as unknown as Record<string, unknown>,
      schema: RECOURSE_EXTENSION_SCHEMA as unknown as Record<string, unknown>,
    },
  };
}

const HEX_20 = /^0x[0-9a-fA-F]{40}$/;
const HEX_32 = /^0x[0-9a-fA-F]{64}$/;

/**
 * Reads the extension out of a PaymentRequired. Returns null when the server did
 * not offer it, which is a valid unprotected payment rather than an error; throws
 * only when the extension is present but malformed, because a buyer must never
 * infer terms from a field it could not parse.
 */
export function readRecourseExtension(extensions: Extensions | undefined): RecourseExtensionInfo | null {
  const entry: Extension | undefined = extensions?.[RECOURSE_EXTENSION_ID];
  if (!entry) return null;
  if (!entry.info || typeof entry.info !== "object") {
    throw new X402Error("recourse/v1 extension carries no info object.", "invalid_extension");
  }

  const info = entry.info as Record<string, unknown>;
  const str = (key: string, pattern?: RegExp): string => {
    const value = info[key];
    if (typeof value !== "string" || (pattern && !pattern.test(value))) {
      throw new X402Error(`recourse/v1 extension field ${key} is missing or malformed.`, "invalid_extension");
    }
    return value;
  };

  const disputeWindow = info.disputeWindow;
  if (typeof disputeWindow !== "number" || !Number.isInteger(disputeWindow) || disputeWindow < 1) {
    throw new X402Error("recourse/v1 extension field disputeWindow is missing or malformed.", "invalid_extension");
  }

  return {
    policyId: str("policyId", /^[0-9]+$/),
    policyHash: str("policyHash", HEX_32) as `0x${string}`,
    agreementHash: str("agreementHash", HEX_32) as `0x${string}`,
    merchant: str("merchant", HEX_20) as `0x${string}`,
    attestor: str("attestor", HEX_20) as `0x${string}`,
    escrow: str("escrow", HEX_20) as `0x${string}`,
    disputeWindow,
    engineVersion: str("engineVersion"),
  };
}

/**
 * Builds the client's extensions block. The spec allows a client to append info but
 * never to delete or overwrite what the server sent, so this merges additions
 * underneath the received values rather than over them.
 */
export function echoExtensions(received: Extensions | undefined, additions: Extensions = {}): Extensions {
  const out: Extensions = {};
  for (const [id, entry] of Object.entries(additions)) {
    out[id] = { info: { ...entry.info }, schema: { ...entry.schema } };
  }
  for (const [id, entry] of Object.entries(received ?? {})) {
    out[id] = {
      // Server values last, so an addition sharing a key cannot displace one.
      info: { ...(out[id]?.info ?? {}), ...entry.info },
      schema: { ...entry.schema },
    };
  }
  return out;
}

/**
 * Server side check of that same rule. A client that dropped or rewrote an
 * advertised term is claiming to have agreed to something else, so the payment is
 * rejected rather than settled against terms nobody offered.
 */
export function assertExtensionsEchoed(sent: Extensions | undefined, echoed: Extensions | undefined): void {
  for (const [id, entry] of Object.entries(sent ?? {})) {
    const back = echoed?.[id];
    if (!back) throw new X402Error(`Client dropped the ${id} extension.`, "extension_not_echoed");
    for (const [key, value] of Object.entries(entry.info)) {
      if (JSON.stringify(back.info?.[key]) !== JSON.stringify(value)) {
        throw new X402Error(`Client altered ${id}.${key}.`, "extension_not_echoed");
      }
    }
  }
}
