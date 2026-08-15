// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Rule} from "../src/Types.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {MockUSYCAdapter} from "../src/MockUSYCAdapter.sol";
import {RecourseEscrow} from "../src/RecourseEscrow.sol";
import {TestUSDC} from "./mocks/TestUSDC.sol";
import {SessionReader} from "./SessionReader.sol";

// Two halves of the same guarantee, docs/agent-settlement.md section A4.
//
// The call log fold is asserted against packages/vectors/session-roots.json, which
// the TS session module asserts against too, so the buyer's SDK and this
// implementation cannot drift apart silently.
//
// The evidence fold is asserted against the real fileDispute rather than a copy of
// its loop, because the value that matters is the one actually written to storage.
contract SessionEvidenceTest is Test, SessionReader {
    TestUSDC usdc;
    PolicyRegistry registry;
    MockUSYCAdapter adapter;
    RecourseEscrow escrow;

    address merchant;
    address buyer;
    uint256 policyId;
    string rootsJson;

    uint128 constant AMOUNT = 10e6;
    uint32 constant DISPUTE_WINDOW = 14 days;

    function setUp() public {
        _loadSessions();
        rootsJson = vm.readFile(string.concat(vm.projectRoot(), "/../packages/vectors/session-roots.json"));

        merchant = makeAddr("merchant");
        buyer = makeAddr("buyer");

        usdc = new TestUSDC();
        registry = new PolicyRegistry();
        adapter = new MockUSYCAdapter(usdc);
        escrow = new RecourseEscrow(usdc, registry, adapter, makeAddr("attestor"), makeAddr("treasury"), 1000, 60);

        vm.prank(merchant);
        policyId = registry.registerPolicy(DISPUTE_WINDOW, 5000, new Rule[](0), "ipfs://agent-policy");

        usdc.mint(buyer, 10_000e6);
        vm.prank(buyer);
        usdc.approve(address(escrow), type(uint256).max);
    }

    function test_callLogRootsMatchGoldenFile() public view {
        string[] memory names = _sessionNames();
        assertGt(names.length, 0, "no sessions loaded");
        for (uint256 k = 0; k < names.length; k++) {
            bytes32 want = vm.parseJsonBytes32(rootsJson, string.concat("$.sessions.", names[k]));
            assertEq(_callLogRoot(_readCalls(names[k])), want, names[k]);
        }
    }

    // An empty log folds to zero, which is why a session with no calls is
    // NOT_SERVED rather than a partial failure: the root carries no information.
    function test_emptySessionFoldsToZero() public view {
        assertEq(_callLogRoot(_readCalls("session-empty")), bytes32(0));
    }

    // The fold is order dependent by construction. Two sessions holding the same
    // calls in a different order must not be interchangeable, or a merchant could
    // reorder a log to match a root it prefers.
    function test_reorderingTheSameCallsChangesTheRoot() public view {
        assertTrue(
            _callLogRoot(_readCalls("session-order-sensitive-a")) != _callLogRoot(_readCalls("session-order-sensitive-b")),
            "reordered log produced the same root"
        );
    }

    function test_fileDisputeStoresTheGoldenEvidenceRoot() public {
        string[] memory names = _evidenceNames();
        assertGt(names.length, 0, "no evidence fixtures loaded");

        for (uint256 k = 0; k < names.length; k++) {
            EvidenceFixture[] memory fixture = _readEvidence(names[k]);

            RecourseEscrow.EvidenceItem[] memory items = new RecourseEscrow.EvidenceItem[](fixture.length);
            for (uint256 j = 0; j < fixture.length; j++) {
                items[j] = RecourseEscrow.EvidenceItem({evType: fixture[j].evType, hash: fixture[j].hash});
            }

            vm.prank(buyer);
            uint256 paymentId = escrow.pay(policyId, AMOUNT, keccak256(abi.encodePacked(names[k])));
            vm.prank(buyer);
            escrow.fileDispute(paymentId, 8, items);

            RecourseEscrow.Payment memory pmt = escrow.getPayment(paymentId);
            assertEq(
                pmt.evidenceRoot,
                vm.parseJsonBytes32(rootsJson, string.concat("$.evidence.", names[k], ".evidenceRoot")),
                string.concat(names[k], ": evidenceRoot")
            );
            assertEq(
                uint256(pmt.evidenceMask),
                vm.parseJsonUint(rootsJson, string.concat("$.evidence.", names[k], ".evidenceMask")),
                string.concat(names[k], ": evidenceMask")
            );
        }
    }

    // Same bits set, different order. The mask cannot tell them apart and the root
    // must, otherwise evidence order would be forgeable.
    function test_maskIgnoresOrderButRootDoesNot() public view {
        uint256 forward = vm.parseJsonUint(rootsJson, "$.evidence.evidence-log-and-schema.evidenceMask");
        uint256 swapped = vm.parseJsonUint(rootsJson, "$.evidence.evidence-order-swapped.evidenceMask");
        assertEq(forward, swapped, "mask should be order independent");
        assertEq(forward, 48, "16 | 32");

        assertTrue(
            vm.parseJsonBytes32(rootsJson, "$.evidence.evidence-log-and-schema.evidenceRoot")
                != vm.parseJsonBytes32(rootsJson, "$.evidence.evidence-order-swapped.evidenceRoot"),
            "root should be order dependent"
        );
    }
}
