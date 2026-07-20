// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Policy, Rule, VerdictInput, Verdict} from "./Types.sol";

// The canonical verdict engine. Pure, no storage, no block context beyond the
// timestamps passed in the input. Exactly one mirror exists (engine/ in TypeScript);
// the two are chained by packages/vectors/verdicts.json. Any change here updates the
// vectors and keeps both suites green in the same commit.
library PolicyEngine {
    // Sentinel ruleIndex meaning "no rule matched, defaultRefundBps applied".
    uint8 internal constant NO_RULE = 255;

    // Gas bound also enforced by PolicyRegistry at registration time.
    uint256 internal constant MAX_RULES = 16;

    function compute(Policy memory p, VerdictInput memory i) internal pure returns (Verdict memory) {
        uint256 n = p.rules.length;
        if (n > MAX_RULES) n = MAX_RULES;

        for (uint256 idx = 0; idx < n; idx++) {
            Rule memory r = p.rules[idx];

            if (r.claimType != i.claimType) continue;

            // Every required evidence bit must be present in the submitted mask.
            if (i.evidenceMask & r.requiredEvidenceMask != r.requiredEvidenceMask) continue;

            // A rule that requires an attestation only matches when the same
            // attestation type carries the expected value.
            if (r.attType != 0) {
                if (i.attType != r.attType) continue;
                if (i.attValue != r.attExpected) continue;
            }

            // filedAt must fall within [paidAt, paidAt + claimWindow], inclusive.
            if (i.filedAt < i.paidAt) continue;
            if (i.filedAt > uint256(i.paidAt) + r.claimWindow) continue;

            return Verdict({refundBps: r.refundBps, requiresReturn: r.requiresReturn, ruleIndex: uint8(idx), matched: true});
        }

        return Verdict({refundBps: p.defaultRefundBps, requiresReturn: false, ruleIndex: NO_RULE, matched: false});
    }

    function verdictHash(bytes32 policyHash, uint256 paymentId, VerdictInput memory i, Verdict memory v)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(policyHash, paymentId, i, v));
    }
}
