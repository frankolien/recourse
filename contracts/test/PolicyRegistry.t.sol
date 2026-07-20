// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Policy, Rule} from "../src/Types.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";

contract PolicyRegistryTest is Test {
    PolicyRegistry registry;

    function setUp() public {
        registry = new PolicyRegistry();
    }

    function _sampleRules() internal pure returns (Rule[] memory rules) {
        rules = new Rule[](1);
        rules[0] = Rule({
            claimType: 1,
            requiredEvidenceMask: 1,
            attType: 0,
            attExpected: 0,
            claimWindow: 259200,
            refundBps: 10000,
            requiresReturn: true
        });
    }

    function test_idsIncrementFromOne() public {
        uint256 id1 = registry.registerPolicy(1209600, 0, _sampleRules(), "ipfs://a");
        uint256 id2 = registry.registerPolicy(1209600, 0, _sampleRules(), "ipfs://b");
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(registry.policyCount(), 2);
    }

    function test_getPolicyRoundTrips() public {
        uint256 id = registry.registerPolicy(1209600, 250, _sampleRules(), "ipfs://a");
        Policy memory p = registry.getPolicy(id);
        assertEq(p.merchant, address(this));
        assertEq(p.disputeWindow, 1209600);
        assertEq(p.defaultRefundBps, 250);
        assertEq(p.rules.length, 1);
        assertEq(p.rules[0].refundBps, 10000);
        assertTrue(p.rules[0].requiresReturn);
    }

    // Locks the hash formula the escrow pins and the TS mirror reproduces.
    function test_policyHashMatchesEncoding() public {
        Rule[] memory rules = _sampleRules();
        uint256 id = registry.registerPolicy(1209600, 0, rules, "ipfs://a");
        bytes32 expected = keccak256(abi.encode(address(this), uint32(1209600), uint16(0), rules));
        assertEq(registry.policyHash(id), expected);
    }

    function test_revertsOnTooManyRules() public {
        Rule[] memory rules = new Rule[](17);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.TooManyRules.selector, uint256(17)));
        registry.registerPolicy(1209600, 0, rules, "ipfs://a");
    }
}
