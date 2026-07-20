// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Policy, VerdictInput, Verdict} from "../src/Types.sol";
import {PolicyEngine} from "../src/PolicyEngine.sol";
import {VectorReader} from "./VectorReader.sol";

// Drives PolicyEngine.compute from packages/vectors/verdicts.json and pins the
// canonical policyHash/verdictHash against packages/vectors/hashes.json. The TS
// mirror asserts against the same two files, so this suite and vitest are the two
// ends of the determinism spine. Regenerate hashes.json (script/GenVectorHashes)
// whenever the engine or vectors change.
contract PolicyEngineVectorsTest is Test, VectorReader {
    string hashesJson;

    function setUp() public {
        _loadVectors();
        hashesJson = vm.readFile(string.concat(vm.projectRoot(), "/../packages/vectors/hashes.json"));
    }

    function test_allVectors() public view {
        string[] memory names = _caseNames();
        assertGt(names.length, 0, "no vectors loaded");
        for (uint256 k = 0; k < names.length; k++) {
            _runCase(names[k]);
        }
    }

    function _runCase(string memory name) internal view {
        string memory base = string.concat(".", name);
        Policy memory p = _readPolicy(base);
        VerdictInput memory i = _readInput(base);
        Verdict memory got = PolicyEngine.compute(p, i);

        string memory e = string.concat(base, ".expect");
        assertEq(got.refundBps, uint16(vm.parseJsonUint(vectorsJson, string.concat(e, ".refundBps"))), string.concat(name, ": refundBps"));
        assertEq(got.requiresReturn, vm.parseJsonBool(vectorsJson, string.concat(e, ".requiresReturn")), string.concat(name, ": requiresReturn"));
        assertEq(got.ruleIndex, uint8(vm.parseJsonUint(vectorsJson, string.concat(e, ".ruleIndex"))), string.concat(name, ": ruleIndex"));
        assertEq(got.matched, vm.parseJsonBool(vectorsJson, string.concat(e, ".matched")), string.concat(name, ": matched"));

        bytes32 ph = _policyHash(p);
        bytes32 vh = PolicyEngine.verdictHash(ph, _readPaymentId(base), i, got);
        assertEq(ph, vm.parseJsonBytes32(hashesJson, string.concat(base, ".policyHash")), string.concat(name, ": policyHash"));
        assertEq(vh, vm.parseJsonBytes32(hashesJson, string.concat(base, ".verdictHash")), string.concat(name, ": verdictHash"));
    }
}
