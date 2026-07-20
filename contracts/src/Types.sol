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
