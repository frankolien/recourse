// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Policy, VerdictInput, Verdict} from "../src/Types.sol";
import {PolicyEngine} from "../src/PolicyEngine.sol";
import {VectorReader} from "../test/VectorReader.sol";

// Generates packages/vectors/hashes.json: the canonical policyHash and verdictHash
// per case, computed by the Solidity engine (the source of truth). The forge suite
// and the TS mirror both assert against this file. Run after any engine or vector
// change:  forge script script/GenVectorHashes.s.sol:GenVectorHashes
contract GenVectorHashes is Script, VectorReader {
    function run() external {
        _loadVectors();
        string[] memory names = _caseNames();

        string memory root;
        for (uint256 k = 0; k < names.length; k++) {
            string memory name = names[k];
            string memory base = string.concat(".", name);

            Policy memory p = _readPolicy(base);
            VerdictInput memory i = _readInput(base);
            Verdict memory v = PolicyEngine.compute(p, i);

            bytes32 ph = _policyHash(p);
            bytes32 vh = PolicyEngine.verdictHash(ph, _readPaymentId(base), i, v);

            vm.serializeBytes32(name, "policyHash", ph);
            string memory inner = vm.serializeBytes32(name, "verdictHash", vh);
            root = vm.serializeString("recourseVectorHashes", name, inner);
        }

        vm.writeJson(root, string.concat(vm.projectRoot(), "/../packages/vectors/hashes.json"));
    }
}
