// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {Policy, Rule, VerdictInput} from "../src/Types.sol";

// Shared reader for packages/vectors/verdicts.json, inherited by both the test
// suite and the hash-generator script so they decode the golden file identically.
// CommonBase supplies `vm`, so this composes with both Test and Script.
abstract contract VectorReader is CommonBase {
    string internal vectorsJson;

    function _loadVectors() internal {
        vectorsJson = vm.readFile(string.concat(vm.projectRoot(), "/../packages/vectors/verdicts.json"));
    }

    function _caseNames() internal view returns (string[] memory) {
        return vm.parseJsonKeys(vectorsJson, "$");
    }

    function _readPolicy(string memory base) internal view returns (Policy memory p) {
        string memory pp = string.concat(base, ".policy");
        p.merchant = vm.parseJsonAddress(vectorsJson, string.concat(pp, ".merchant"));
        p.disputeWindow = uint32(vm.parseJsonUint(vectorsJson, string.concat(pp, ".disputeWindow")));
        p.defaultRefundBps = uint16(vm.parseJsonUint(vectorsJson, string.concat(pp, ".defaultRefundBps")));

        string memory rr = string.concat(pp, ".rules");
        uint256[] memory claimType = vm.parseJsonUintArray(vectorsJson, string.concat(rr, ".claimType"));
        uint256[] memory mask = vm.parseJsonUintArray(vectorsJson, string.concat(rr, ".requiredEvidenceMask"));
        uint256[] memory attType = vm.parseJsonUintArray(vectorsJson, string.concat(rr, ".attType"));
        uint256[] memory attExpected = vm.parseJsonUintArray(vectorsJson, string.concat(rr, ".attExpected"));
        uint256[] memory claimWindow = vm.parseJsonUintArray(vectorsJson, string.concat(rr, ".claimWindow"));
        uint256[] memory refundBps = vm.parseJsonUintArray(vectorsJson, string.concat(rr, ".refundBps"));
        bool[] memory requiresReturn = vm.parseJsonBoolArray(vectorsJson, string.concat(rr, ".requiresReturn"));

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
        i.claimType = uint8(vm.parseJsonUint(vectorsJson, string.concat(ii, ".claimType")));
        i.evidenceMask = uint16(vm.parseJsonUint(vectorsJson, string.concat(ii, ".evidenceMask")));
        i.attType = uint8(vm.parseJsonUint(vectorsJson, string.concat(ii, ".attType")));
        i.attValue = uint8(vm.parseJsonUint(vectorsJson, string.concat(ii, ".attValue")));
        i.paidAt = uint64(vm.parseJsonUint(vectorsJson, string.concat(ii, ".paidAt")));
        i.filedAt = uint64(vm.parseJsonUint(vectorsJson, string.concat(ii, ".filedAt")));
    }

    function _readPaymentId(string memory base) internal view returns (uint256) {
        return vm.parseJsonUint(vectorsJson, string.concat(base, ".paymentId"));
    }

    // The canonical policyHash formula, matching PolicyRegistry.
    function _policyHash(Policy memory p) internal pure returns (bytes32) {
        return keccak256(abi.encode(p.merchant, p.disputeWindow, p.defaultRefundBps, p.rules));
    }
}
