// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Policy, Rule, VerdictInput, Verdict} from "../src/Types.sol";
import {PolicyEngine} from "../src/PolicyEngine.sol";

// Drives PolicyEngine.compute from packages/vectors/verdicts.json. The TS mirror
// asserts against the same file, so this suite and vitest are the two ends of the
// determinism spine.
contract PolicyEngineVectorsTest is Test {
    string json;

    function setUp() public {
        json = vm.readFile(string.concat(vm.projectRoot(), "/../packages/vectors/verdicts.json"));
    }

    function test_allVectors() public view {
        string[] memory names = vm.parseJsonKeys(json, "$");
        assertGt(names.length, 0, "no vectors loaded");
        for (uint256 k = 0; k < names.length; k++) {
            _runCase(names[k]);
        }
    }

    function _runCase(string memory name) internal view {
        string memory base = string.concat(".", name);
        Verdict memory got = PolicyEngine.compute(_readPolicy(base), _readInput(base));

        string memory e = string.concat(base, ".expect");
        assertEq(got.refundBps, uint16(vm.parseJsonUint(json, string.concat(e, ".refundBps"))), string.concat(name, ": refundBps"));
        assertEq(got.requiresReturn, vm.parseJsonBool(json, string.concat(e, ".requiresReturn")), string.concat(name, ": requiresReturn"));
        assertEq(got.ruleIndex, uint8(vm.parseJsonUint(json, string.concat(e, ".ruleIndex"))), string.concat(name, ": ruleIndex"));
        assertEq(got.matched, vm.parseJsonBool(json, string.concat(e, ".matched")), string.concat(name, ": matched"));
    }

    function _readPolicy(string memory base) internal view returns (Policy memory p) {
        string memory pp = string.concat(base, ".policy");
        p.merchant = vm.parseJsonAddress(json, string.concat(pp, ".merchant"));
        p.disputeWindow = uint32(vm.parseJsonUint(json, string.concat(pp, ".disputeWindow")));
        p.defaultRefundBps = uint16(vm.parseJsonUint(json, string.concat(pp, ".defaultRefundBps")));

        string memory rr = string.concat(pp, ".rules");
        uint256[] memory claimType = vm.parseJsonUintArray(json, string.concat(rr, ".claimType"));
        uint256[] memory mask = vm.parseJsonUintArray(json, string.concat(rr, ".requiredEvidenceMask"));
        uint256[] memory attType = vm.parseJsonUintArray(json, string.concat(rr, ".attType"));
        uint256[] memory attExpected = vm.parseJsonUintArray(json, string.concat(rr, ".attExpected"));
        uint256[] memory claimWindow = vm.parseJsonUintArray(json, string.concat(rr, ".claimWindow"));
        uint256[] memory refundBps = vm.parseJsonUintArray(json, string.concat(rr, ".refundBps"));
        bool[] memory requiresReturn = vm.parseJsonBoolArray(json, string.concat(rr, ".requiresReturn"));

        p.rules = new Rule[](claimType.length);
        for (uint256 k = 0; k < claimType.length; k++) {
            p.rules[k] = Rule({
                claimType: uint8(claimType[k]),
                requiredEvidenceMask: uint16(mask[k]),
                attType: uint8(attType[k]),
                attExpected: uint8(attExpected[k]),
                claimWindow: uint32(claimWindow[k]),
                refundBps: uint16(refundBps[k]),
                requiresReturn: requiresReturn[k]
            });
        }
    }

    function _readInput(string memory base) internal view returns (VerdictInput memory i) {
        string memory ii = string.concat(base, ".input");
        i.claimType = uint8(vm.parseJsonUint(json, string.concat(ii, ".claimType")));
        i.evidenceMask = uint16(vm.parseJsonUint(json, string.concat(ii, ".evidenceMask")));
        i.attType = uint8(vm.parseJsonUint(json, string.concat(ii, ".attType")));
        i.attValue = uint8(vm.parseJsonUint(json, string.concat(ii, ".attValue")));
        i.paidAt = uint64(vm.parseJsonUint(json, string.concat(ii, ".paidAt")));
        i.filedAt = uint64(vm.parseJsonUint(json, string.concat(ii, ".filedAt")));
    }
}
