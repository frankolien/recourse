// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";

// Shared reader for packages/vectors/sessions.json, inherited by the test suite
// and the root-generator script so both decode the fixture identically. Mirrors
// the arrangement VectorReader already uses for verdicts.json.
//
// The callLogRoot fold below is a second, independent implementation of what
// engine/src/session.ts does. It exists precisely so the two can disagree in a
// test rather than in production: a buyer and a merchant deriving different roots
// from the same log is a dispute that cannot be verified by anyone.
abstract contract SessionReader is CommonBase {
    struct CallRecord {
        bytes32 requestHash;
        bytes32 responseHash;
        uint16 statusCode;
        uint32 latencyMs;
        bool schemaValid;
    }

    struct EvidenceFixture {
        uint8 evType;
        bytes32 hash;
    }

    string internal sessionsJson;

    function _loadSessions() internal {
        sessionsJson = vm.readFile(string.concat(vm.projectRoot(), "/../packages/vectors/sessions.json"));
    }

    function _sessionNames() internal view returns (string[] memory) {
        return vm.parseJsonKeys(sessionsJson, "$.sessions");
    }

    function _evidenceNames() internal view returns (string[] memory) {
        return vm.parseJsonKeys(sessionsJson, "$.evidence");
    }

    function _readCalls(string memory name) internal view returns (CallRecord[] memory records) {
        string memory base = string.concat("$.sessions.", name, ".calls.");
        bytes32[] memory requestHash = vm.parseJsonBytes32Array(sessionsJson, string.concat(base, "requestHash"));
        bytes32[] memory responseHash = vm.parseJsonBytes32Array(sessionsJson, string.concat(base, "responseHash"));
        uint256[] memory statusCode = vm.parseJsonUintArray(sessionsJson, string.concat(base, "statusCode"));
        uint256[] memory latencyMs = vm.parseJsonUintArray(sessionsJson, string.concat(base, "latencyMs"));
        bool[] memory schemaValid = vm.parseJsonBoolArray(sessionsJson, string.concat(base, "schemaValid"));

        records = new CallRecord[](requestHash.length);
        for (uint256 k = 0; k < requestHash.length; k++) {
            records[k] = CallRecord({
                requestHash: requestHash[k],
                responseHash: responseHash[k],
                statusCode: uint16(statusCode[k]),
                latencyMs: uint32(latencyMs[k]),
                schemaValid: schemaValid[k]
            });
        }
    }

    function _readEvidence(string memory name) internal view returns (EvidenceFixture[] memory items) {
        string memory base = string.concat("$.evidence.", name, ".items.");
        uint256[] memory evType = vm.parseJsonUintArray(sessionsJson, string.concat(base, "evType"));
        bytes32[] memory hashes = vm.parseJsonBytes32Array(sessionsJson, string.concat(base, "hash"));

        items = new EvidenceFixture[](evType.length);
        for (uint256 k = 0; k < evType.length; k++) {
            items[k] = EvidenceFixture({evType: uint8(evType[k]), hash: hashes[k]});
        }
    }

    function _callHash(uint256 index, CallRecord memory c) internal pure returns (bytes32) {
        return keccak256(abi.encode(index, c.requestHash, c.responseHash, c.statusCode, c.latencyMs, c.schemaValid));
    }

    // L[0] = 0; L[i] = keccak256(abi.encodePacked(L[i-1], h[i])).
    function _callLogRoot(CallRecord[] memory records) internal pure returns (bytes32 root) {
        for (uint256 k = 0; k < records.length; k++) {
            root = keccak256(abi.encodePacked(root, _callHash(k, records[k])));
        }
    }
}
