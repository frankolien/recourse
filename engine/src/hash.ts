import { encodeAbiParameters, keccak256 } from "viem";
import { policyHashParams, verdictHashParams } from "./abi";
import type { Policy, VerdictInput, Verdict } from "./types";

// Reproduces PolicyRegistry's policyHash. The merchant is lowercased before
// encoding to bypass viem's checksum validation; the encoded 20 bytes (and so the
// hash) are identical regardless of address casing.
export function policyHash(p: Policy): `0x${string}` {
  return keccak256(
    encodeAbiParameters(policyHashParams, [
      p.merchant.toLowerCase() as `0x${string}`,
      p.disputeWindow,
      p.defaultRefundBps,
      p.rules.map((r) => ({
        claimType: r.claimType,
        requiredEvidenceMask: r.requiredEvidenceMask,
        attType: r.attType,
        attExpected: r.attExpected,
        claimWindow: r.claimWindow,
        refundBps: r.refundBps,
        requiresReturn: r.requiresReturn,
      })),
    ]),
  );
}

// Reproduces PolicyEngine.verdictHash.
export function verdictHash(
  policyHashValue: `0x${string}`,
  paymentId: bigint,
  i: VerdictInput,
  v: Verdict,
): `0x${string}` {
  return keccak256(
    encodeAbiParameters(verdictHashParams, [
      policyHashValue,
      paymentId,
      {
        claimType: i.claimType,
        evidenceMask: i.evidenceMask,
        attType: i.attType,
        attValue: i.attValue,
        paidAt: i.paidAt,
        filedAt: i.filedAt,
      },
      {
        refundBps: v.refundBps,
        requiresReturn: v.requiresReturn,
        ruleIndex: v.ruleIndex,
        matched: v.matched,
      },
    ]),
  );
}
