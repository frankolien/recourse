import { describe, it, expect } from "vitest";
import { keccak256, toHex } from "viem";

// Byte-identical to the fixtures in backend/src/services/orders.rs and
// mobile/RecourseTests/OrderManifestTests.swift. An order manifest binds to the chain by
// hash-of-exact-bytes: orderRef = keccak256(document), so cross-language agreement is
// agreement on this one value. If the fixture changes, update all three in one commit.
const FIXTURE =
  '{"version":1,"chainId":5042002,"escrow":"0x61Fd99789B28582882a3369E2024AeaE5b5D2DC0","merchant":"0xD6c574461d96Ee708f58Fe553049aD4f48BB983A","policyId":1,"amount":"250000","orderReference":"ORDER-1001","itemName":"API Credits Pack","description":"1,000 cloud compute credits","createdAt":1784900000}';

const GOLDEN_ORDER_REF =
  "0xa4e970942b2f79b3ef97bd7cbb6a64dd5c92ce63e6c6facc758792f69a88b7cd";

describe("order manifest hashing", () => {
  it("orderRef is keccak256 of the exact manifest bytes", () => {
    expect(keccak256(toHex(FIXTURE))).toBe(GOLDEN_ORDER_REF);
  });

  it("any byte change produces a different orderRef", () => {
    const tampered = FIXTURE.replace('"250000"', '"250001"');
    expect(keccak256(toHex(tampered))).not.toBe(GOLDEN_ORDER_REF);
  });
});
