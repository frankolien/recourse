// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {SessionReader} from "../test/SessionReader.sol";

// Generates packages/vectors/session-roots.json: the canonical callLogRoot per
// session and evidenceRoot per evidence fixture, computed in Solidity. The forge
// suite and the TS session module both assert against this file, the same way
// hashes.json anchors the verdict engine. Run after any change to the fold or the
// fixtures:  forge script script/GenSessionRoots.s.sol:GenSessionRoots
contract GenSessionRoots is Script, SessionReader {
    function run() external {
        _loadSessions();

        string memory sessionsOut;
        string[] memory sessions = _sessionNames();
        for (uint256 k = 0; k < sessions.length; k++) {
            sessionsOut = vm.serializeBytes32("sessionRoots", sessions[k], _callLogRoot(_readCalls(sessions[k])));
        }

        string memory evidenceOut;
        string[] memory evidence = _evidenceNames();
        for (uint256 k = 0; k < evidence.length; k++) {
            EvidenceFixture[] memory items = _readEvidence(evidence[k]);
            bytes32 root;
            uint16 mask;
            for (uint256 j = 0; j < items.length; j++) {
                mask |= items[j].evType;
                root = keccak256(abi.encodePacked(root, items[j].evType, items[j].hash));
            }
            vm.serializeUint(evidence[k], "evidenceMask", mask);
            string memory inner = vm.serializeBytes32(evidence[k], "evidenceRoot", root);
            evidenceOut = vm.serializeString("evidenceRoots", evidence[k], inner);
        }

        vm.serializeString("root", "sessions", sessionsOut);
        string memory out = vm.serializeString("root", "evidence", evidenceOut);
        vm.writeJson(out, string.concat(vm.projectRoot(), "/../packages/vectors/session-roots.json"));
    }
}
