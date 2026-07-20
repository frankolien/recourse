// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Policy, Rule} from "./Types.sol";
import {PolicyEngine} from "./PolicyEngine.sol";

// Immutable store of refund policies. Editing a policy is not supported by design:
// a change registers a new policyId, so a payment pinned to a policyHash can never
// have its rules altered after the fact.
contract PolicyRegistry {
    mapping(uint256 => Policy) private _policies;
    mapping(uint256 => bytes32) private _policyHash;

    // Last assigned id; ids start at 1 so that 0 reads as "no policy".
    uint256 public policyCount;

    event PolicyRegistered(uint256 indexed policyId, address indexed merchant, bytes32 policyHash, string metadataURI);

    error TooManyRules(uint256 count);

    function registerPolicy(uint32 disputeWindow, uint16 defaultRefundBps, Rule[] calldata rules, string calldata metadataURI)
        external
        returns (uint256 policyId)
    {
        if (rules.length > PolicyEngine.MAX_RULES) revert TooManyRules(rules.length);

        policyId = ++policyCount;

        Policy storage p = _policies[policyId];
        p.merchant = msg.sender;
        p.disputeWindow = disputeWindow;
        p.defaultRefundBps = defaultRefundBps;
        for (uint256 k = 0; k < rules.length; k++) {
            p.rules.push(rules[k]);
        }

        // Hash covers the on-chain encoding, not the authored JSON. The TS mirror
        // encodes the same component order (address, uint32, uint16, Rule[]).
        bytes32 h = keccak256(abi.encode(msg.sender, disputeWindow, defaultRefundBps, rules));
        _policyHash[policyId] = h;

        emit PolicyRegistered(policyId, msg.sender, h, metadataURI);
    }

    function getPolicy(uint256 policyId) external view returns (Policy memory) {
        return _policies[policyId];
    }

    function policyHash(uint256 policyId) external view returns (bytes32) {
        return _policyHash[policyId];
    }
}
