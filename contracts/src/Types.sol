// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Canonical on-chain types shared by the registry, engine, and escrow.
// Field order here is load-bearing: policyHash and verdictHash are keccak256
// over abi.encode of these structs, and the TS engine mirror encodes the same
// component order. Reordering fields silently breaks hash parity.

// uint8; index doubles as the on-chain claimType value used in rules and inputs.
enum ClaimType {
    NotDelivered, // 0
    Damaged, // 1
    NotAsDescribed, // 2
    WrongItem, // 3
    Other // 4
}

// Evidence type bitmask: 1 = PHOTO, 2 = DESCRIPTION, 4 = TRACKING_REF, 8 = VIDEO.
// Attestation types: 0 = NONE, 1 = DELIVERY_STATUS.
// DELIVERY_STATUS values: 0 = UNKNOWN, 1 = DELIVERED, 2 = NOT_DELIVERED.

// Agent commerce vocabulary, docs/agent-settlement.md sections A1 and A2.
// PolicyEngine compares these values and never interprets them, so the parcel
// range and the agent range share one uint8 with no change to matching. Declared
// as constants rather than an enum because Solidity enums must start at zero and
// these continue an existing numbering.
uint8 constant CLAIM_NOT_SERVED = 5;
uint8 constant CLAIM_SCHEMA_VIOLATION = 6;
uint8 constant CLAIM_SLA_BREACH = 7;
uint8 constant CLAIM_PARTIAL_FAILURE = 8;

// evType is uint8, so eight evidence bits exist. Four are spent on the parcel
// vocabulary above and these are the remaining four.
uint8 constant EV_CALL_LOG_ROOT = 16;
uint8 constant EV_SCHEMA_FAILURE = 32;
uint8 constant EV_SLA_MEASUREMENT = 64;
uint8 constant EV_UNREACHABLE = 128;

// Attestation type 2. The value is a severity bucket, not a measurement: the
// engine can only test equality, so the attestor quantises the observed failure
// rate and the policy carries one rule per bucket.
uint8 constant ATT_SLA_OUTCOME = 2;

uint8 constant SLA_CLEAN = 0;
uint8 constant SLA_MINOR = 1;
uint8 constant SLA_MODERATE = 2;
uint8 constant SLA_SEVERE = 3;
uint8 constant SLA_TOTAL = 4;

struct Rule {
    uint8 claimType;
    uint16 requiredEvidenceMask;
    uint8 attType; // 0 none, 1 delivery_status
    uint8 attExpected; // required attested value when attType != 0
    uint32 claimWindow; // seconds from paidAt within which the claim must be filed
    uint16 refundBps;
    bool requiresReturn;
}

struct Policy {
    address merchant;
    uint32 disputeWindow; // seconds; escrow-level window for filing any dispute
    uint16 defaultRefundBps; // applied when no rule matches
    Rule[] rules; // max 16, evaluated in order, first match wins
}

struct VerdictInput {
    uint8 claimType;
    uint16 evidenceMask;
    uint8 attType;
    uint8 attValue;
    uint64 paidAt;
    uint64 filedAt;
}

struct Verdict {
    uint16 refundBps;
    bool requiresReturn;
    uint8 ruleIndex; // 255 when defaultRefundBps applied
    bool matched;
}
