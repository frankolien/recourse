// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Rule, ClaimType} from "../src/Types.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {MockUSYCAdapter} from "../src/MockUSYCAdapter.sol";
import {RecourseEscrow} from "../src/RecourseEscrow.sol";
import {TestUSDC} from "./mocks/TestUSDC.sol";

// Drives the escrow through random action sequences. Every action is wrapped in
// try/catch so a revert is a no-op rather than a failed run: what is under test is
// the state left behind by whatever sequence succeeds, not which calls are legal.
contract EscrowHandler is Test {
    TestUSDC public immutable usdc;
    RecourseEscrow public immutable escrow;
    MockUSYCAdapter public immutable adapter;
    PolicyRegistry public immutable registry;

    uint256 internal immutable attestorPk;
    address[3] public buyers;
    address public immutable merchant;
    address public immutable treasury;
    uint256 public immutable policyId;

    // Ghost state, read by the invariants.
    mapping(uint256 => uint8) public maxStatusSeen;
    mapping(uint256 => uint256) public settlementCount;
    mapping(uint256 => uint16) public verdictAtSettlement;
    mapping(uint256 => address) public beneficiaryAtSettlement;
    uint256 public settledTotal;
    uint256 public disputesFiled;
    uint256 public attestationsAccepted;

    constructor(
        TestUSDC _usdc,
        PolicyRegistry _registry,
        MockUSYCAdapter _adapter,
        RecourseEscrow _escrow,
        uint256 _attestorPk,
        address _merchant,
        address _treasury,
        uint256 _policyId,
        address[3] memory _buyers
    ) {
        usdc = _usdc;
        registry = _registry;
        adapter = _adapter;
        escrow = _escrow;
        attestorPk = _attestorPk;
        merchant = _merchant;
        treasury = _treasury;
        policyId = _policyId;
        buyers = _buyers;
    }

    function _observe(uint256 paymentId) internal {
        RecourseEscrow.Payment memory pmt = escrow.getPayment(paymentId);
        uint8 status = uint8(pmt.status);
        if (status > maxStatusSeen[paymentId]) maxStatusSeen[paymentId] = status;

        if (pmt.status == RecourseEscrow.Status.Settled && settlementCount[paymentId] == 0) {
            settlementCount[paymentId] = 1;
            verdictAtSettlement[paymentId] = pmt.verdictBps;
            beneficiaryAtSettlement[paymentId] = pmt.beneficiary;
            settledTotal++;
        }
    }

    function _pick(uint256 seed) internal view returns (uint256) {
        uint256 count = escrow.paymentCount();
        return count == 0 ? 0 : bound(seed, 1, count);
    }

    function pay(uint256 actorSeed, uint256 amountSeed) external {
        address buyer = buyers[bound(actorSeed, 0, 2)];
        uint128 amount = uint128(bound(amountSeed, 1e6, 100e6));
        vm.prank(buyer);
        try escrow.pay(policyId, amount, keccak256(abi.encode(amountSeed))) returns (uint256 paymentId) {
            _observe(paymentId);
        } catch {}
    }

    function fileDispute(uint256 paymentSeed, uint256 claimSeed, uint256 evidenceSeed) external {
        uint256 paymentId = _pick(paymentSeed);
        if (paymentId == 0) return;

        RecourseEscrow.EvidenceItem[] memory items = new RecourseEscrow.EvidenceItem[](1);
        items[0] = RecourseEscrow.EvidenceItem({
            evType: uint8(bound(evidenceSeed, 1, 8)),
            hash: keccak256(abi.encode(evidenceSeed))
        });

        vm.prank(escrow.getPayment(paymentId).buyer);
        try escrow.fileDispute(paymentId, uint8(bound(claimSeed, 0, 4)), items) {
            disputesFiled++;
        } catch {}
        _observe(paymentId);
    }

    function attest(uint256 paymentSeed, uint256 valueSeed) external {
        uint256 paymentId = _pick(paymentSeed);
        if (paymentId == 0) return;

        uint8 value = uint8(bound(valueSeed, 0, 2));
        uint64 deadline = uint64(block.timestamp + 1 days);
        bytes32 digest = escrow.attestationDigest(paymentId, 1, value, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorPk, digest);

        try escrow.submitAttestation(paymentId, 1, value, deadline, abi.encodePacked(r, s, v)) {
            attestationsAccepted++;
        } catch {}
        _observe(paymentId);
    }

    function resolve(uint256 paymentSeed) external {
        uint256 paymentId = _pick(paymentSeed);
        if (paymentId == 0) return;
        try escrow.resolve(paymentId) {} catch {}
        _observe(paymentId);
    }

    function release(uint256 paymentSeed) external {
        uint256 paymentId = _pick(paymentSeed);
        if (paymentId == 0) return;
        try escrow.release(paymentId) {} catch {}
        _observe(paymentId);
    }

    function warp(uint256 secondsSeed) external {
        vm.warp(block.timestamp + bound(secondsSeed, 1, 3 days));
    }

    // Re-reads every payment so the ghosts stay current even when a settlement was
    // driven by a call the handler did not make.
    function sweep() external {
        uint256 count = escrow.paymentCount();
        for (uint256 k = 1; k <= count; k++) {
            _observe(k);
        }
    }
}

// Properties I1, I2 and I3 from docs/agent-settlement.md section 5.2. These hold
// over sequences rather than single calls, which is why they are invariants and not
// unit tests.
contract EscrowInvariantsTest is Test {
    TestUSDC usdc;
    PolicyRegistry registry;
    MockUSYCAdapter adapter;
    RecourseEscrow escrow;
    EscrowHandler handler;

    uint256 constant ATTESTOR_PK = 0xA11CE;
    address merchant;
    address treasury;
    address[3] buyers;

    uint256 initialSupply;

    function setUp() public {
        merchant = makeAddr("merchant");
        treasury = makeAddr("treasury");
        buyers = [makeAddr("buyer0"), makeAddr("buyer1"), makeAddr("buyer2")];

        usdc = new TestUSDC();
        registry = new PolicyRegistry();
        adapter = new MockUSYCAdapter(usdc);
        escrow = new RecourseEscrow(usdc, registry, adapter, vm.addr(ATTESTOR_PK), treasury, 1000, 60);

        vm.prank(merchant);
        uint256 policyId = registry.registerPolicy(14 days, 2500, _rules(), "ipfs://policy");

        for (uint256 k = 0; k < buyers.length; k++) {
            usdc.mint(buyers[k], 10_000e6);
        }
        usdc.mint(address(adapter), 100_000e6); // yield buffer, per MockUSYCAdapter

        handler = new EscrowHandler(
            usdc, registry, adapter, escrow, ATTESTOR_PK, merchant, treasury, policyId, buyers
        );

        for (uint256 k = 0; k < buyers.length; k++) {
            vm.prank(buyers[k]);
            usdc.approve(address(escrow), type(uint256).max);
        }

        initialSupply = usdc.totalSupply();
        targetContract(address(handler));
    }

    function _rules() internal pure returns (Rule[] memory rules) {
        rules = new Rule[](2);
        rules[0] = Rule({
            claimType: uint8(ClaimType.NotDelivered),
            requiredEvidenceMask: 0,
            attType: 1,
            attExpected: 2,
            claimWindow: 14 days,
            refundBps: 10000,
            requiresReturn: false
        });
        rules[1] = Rule({
            claimType: uint8(ClaimType.Damaged),
            requiredEvidenceMask: 1,
            attType: 0,
            attExpected: 0,
            claimWindow: 3 days,
            refundBps: 5000,
            requiresReturn: true
        });
    }

    // I1. Nothing mints or burns after setup, so every payout must be funded by a
    // redemption. A settlement paying out more than it redeemed would have to come
    // from somewhere, and this is the only place it could.
    function invariant_usdcIsConserved() public view {
        uint256 held = usdc.balanceOf(address(escrow)) + usdc.balanceOf(address(adapter))
            + usdc.balanceOf(treasury) + usdc.balanceOf(merchant);
        for (uint256 k = 0; k < buyers.length; k++) {
            held += usdc.balanceOf(buyers[k]);
        }
        assertEq(held, initialSupply, "USDC was created or destroyed");
    }

    // The escrow is a conduit, never a vault: principal sweeps into the adapter on
    // pay and leaves entirely on settlement. A non-zero balance between actions
    // means a payout path failed to distribute everything it redeemed.
    function invariant_escrowHoldsNoIdleUsdc() public view {
        assertEq(usdc.balanceOf(address(escrow)), 0, "escrow retained USDC between actions");
    }

    // I2. None -> Paid -> Disputed -> Settled, with release skipping Disputed.
    // Never backwards.
    function invariant_statusNeverRegresses() public view {
        uint256 count = escrow.paymentCount();
        for (uint256 k = 1; k <= count; k++) {
            uint8 current = uint8(escrow.getPayment(k).status);
            assertGe(current, handler.maxStatusSeen(k), "status regressed");
        }
    }

    // I3. Settled is terminal: the verdict and the beneficiary recorded at
    // settlement must still read the same afterwards, so no payment can be settled
    // twice or have its outcome rewritten.
    function invariant_settledPaymentsAreFrozen() public view {
        uint256 count = escrow.paymentCount();
        for (uint256 k = 1; k <= count; k++) {
            if (handler.settlementCount(k) == 0) continue;
            RecourseEscrow.Payment memory pmt = escrow.getPayment(k);
            assertEq(uint8(pmt.status), uint8(RecourseEscrow.Status.Settled), "settled payment left Settled");
            assertEq(pmt.verdictBps, handler.verdictAtSettlement(k), "verdict rewritten after settlement");
            assertEq(pmt.beneficiary, handler.beneficiaryAtSettlement(k), "beneficiary rewritten after settlement");
        }
    }

    // Coverage guard. Every handler action swallows its reverts, so a handler that
    // silently did nothing would satisfy all of the above vacuously.
    //
    // Only that the handler moved at all is asserted here. Anything deeper needs a
    // specific multi-step sequence, and whether a random walk finds one varies
    // between runs: asserting disputes, attestations or settlements here made the
    // suite fail intermittently on a codebase that had not changed. Reachability is
    // a question for a driven test, not a fuzzed one, so it moved to
    // test_handlerReachesSettlementAndAttestation below.
    function afterInvariant() public view {
        assertGt(escrow.paymentCount(), 0, "no payments were opened");
    }

    // The other half of the coverage guard, driven rather than fuzzed. If the
    // handler can no longer reach settlement or get an attestation accepted, every
    // invariant above is passing over a state space that never gets deep enough to
    // be interesting.
    function test_handlerReachesSettlementAndAttestation() public {
        handler.pay(0, 0);
        uint256 paymentId = escrow.paymentCount();
        assertGt(paymentId, 0, "handler could not open a payment");

        handler.fileDispute(paymentId, 0, type(uint256).max);
        assertGt(handler.disputesFiled(), 0, "handler could not file a dispute");

        handler.attest(paymentId, 0);
        assertGt(handler.attestationsAccepted(), 0, "handler could not get an attestation accepted");

        handler.resolve(paymentId);
        assertGt(handler.settledTotal(), 0, "handler could not settle a payment");
    }

    // Adapter shares are only ever minted to the escrow, and a settlement burns
    // exactly the shares that payment holds. Shares outliving their payments would
    // mean principal stranded in the adapter.
    function invariant_openPaymentsAccountForEscrowShares() public view {
        uint256 count = escrow.paymentCount();
        uint256 openShares;
        for (uint256 k = 1; k <= count; k++) {
            RecourseEscrow.Payment memory pmt = escrow.getPayment(k);
            if (pmt.status != RecourseEscrow.Status.Settled) openShares += pmt.shares;
        }
        assertEq(adapter.sharesOf(address(escrow)), openShares, "escrow shares do not match open payments");
    }
}
