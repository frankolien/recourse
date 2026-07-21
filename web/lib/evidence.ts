// Browser-side evidence verification. The escrow stores only the folded evidenceRoot;
// the ordered item list is calldata, so it comes from the backend. But the backend is
// never trusted for the result: the browser re-folds the list here and checks it against
// the evidenceRoot it read from Arc itself. A lying backend just produces a mismatch.

import { encodePacked, keccak256, type Hex } from "viem";
import { API_BASE } from "./api";

export interface EvidenceItem {
  evType: number;
  hash: Hex;
  available?: boolean;
  size?: number | null;
  contentType?: string | null;
}

export interface PaymentEvidence {
  paymentId: number;
  evidenceRoot: Hex;
  hasManifest: boolean;
  matches: boolean;
  computedRoot?: Hex;
  items: EvidenceItem[];
}

export const ZERO_ROOT = `0x${"0".repeat(64)}` as Hex;

export const EVIDENCE_LABELS: Record<number, string> = { 1: "Photo", 2: "Description", 4: "Tracking", 8: "Video" };

export function evidenceLabel(evType: number): string {
  return EVIDENCE_LABELS[evType] ?? `Type ${evType}`;
}

// Mirrors RecourseEscrow.fileDispute byte-for-byte:
//   root = 0; for each item: root = keccak256(abi.encodePacked(root, evType, hash))
export function computeEvidenceRoot(items: EvidenceItem[]): Hex {
  let root: Hex = ZERO_ROOT;
  for (const item of items) {
    root = keccak256(encodePacked(["bytes32", "uint8", "bytes32"], [root, item.evType, item.hash]));
  }
  return root;
}

export async function fetchPaymentEvidence(paymentId: bigint): Promise<PaymentEvidence> {
  const res = await fetch(`${API_BASE}/api/payments/${paymentId}/evidence`, { cache: "no-store" });
  if (!res.ok) throw new Error(`evidence returned ${res.status}`);
  return (await res.json()) as PaymentEvidence;
}

export const evidenceBlobUrl = (hash: string) => `${API_BASE}/api/evidence/${hash}`;
