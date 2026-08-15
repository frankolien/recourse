import { type AbiParameter } from "viem";

// ABI parameter definitions that reproduce Solidity abi.encode byte-for-byte.
// Component order matches the Solidity structs in contracts/src/Types.sol.

export const ruleComponents = [
  { name: "claimType", type: "uint8" },
  { name: "requiredEvidenceMask", type: "uint16" },
  { name: "attType", type: "uint8" },
  { name: "attExpected", type: "uint8" },
  { name: "claimWindow", type: "uint32" },
  { name: "refundBps", type: "uint16" },
  { name: "requiresReturn", type: "bool" },
] as const satisfies readonly AbiParameter[];

// keccak256(abi.encode(merchant, disputeWindow, defaultRefundBps, rules))
export const policyHashParams = [
  { name: "merchant", type: "address" },
  { name: "disputeWindow", type: "uint32" },
  { name: "defaultRefundBps", type: "uint16" },
  { name: "rules", type: "tuple[]", components: ruleComponents },
] as const satisfies readonly AbiParameter[];

export const verdictInputComponents = [
  { name: "claimType", type: "uint8" },
  { name: "evidenceMask", type: "uint16" },
  { name: "attType", type: "uint8" },
  { name: "attValue", type: "uint8" },
  { name: "paidAt", type: "uint64" },
  { name: "filedAt", type: "uint64" },
] as const satisfies readonly AbiParameter[];

export const verdictComponents = [
  { name: "refundBps", type: "uint16" },
  { name: "requiresReturn", type: "bool" },
  { name: "ruleIndex", type: "uint8" },
  { name: "matched", type: "bool" },
] as const satisfies readonly AbiParameter[];

// keccak256(abi.encode(policyHash, paymentId, VerdictInput, Verdict))
export const verdictHashParams = [
  { name: "policyHash", type: "bytes32" },
  { name: "paymentId", type: "uint256" },
  { name: "input", type: "tuple", components: verdictInputComponents },
  { name: "verdict", type: "tuple", components: verdictComponents },
] as const satisfies readonly AbiParameter[];

// keccak256(abi.encode(index, requestHash, responseHash, statusCode, latencyMs, schemaValid))
// per call in a session, docs/agent-settlement.md section A4.
//
// abi.encode pads every value to 32 bytes, so these integer widths do not change
// the bytes and an independent implementation using wider types still derives the
// same hash. What is load bearing is the field order and count. The widths are
// declared to document the accepted range, which session.ts enforces separately;
// the packed folds in that module are where width does change the result.
export const callRecordParams = [
  { name: "index", type: "uint256" },
  { name: "requestHash", type: "bytes32" },
  { name: "responseHash", type: "bytes32" },
  { name: "statusCode", type: "uint16" },
  { name: "latencyMs", type: "uint32" },
  { name: "schemaValid", type: "bool" },
] as const satisfies readonly AbiParameter[];
