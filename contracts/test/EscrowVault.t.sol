// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Rule} from "../src/Types.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {MockUSYCAdapter} from "../src/MockUSYCAdapter.sol";
import {RecourseEscrow} from "../src/RecourseEscrow.sol";
import {SettlementVault} from "../src/SettlementVault.sol";
import {TestUSDC} from "./mocks/TestUSDC.sol";

// End-to-end flows across escrow, adapter, and vault, asserting exact USDC movement
// and value conservation (sum of payouts == redeemed total) on every settlement.
contract EscrowVaultTest is Test {
    TestUSDC usdc;
    PolicyRegistry registry;
    MockUSYCAdapter adapter;
    RecourseEscrow escrow;
    SettlementVault vault;

    uint256 constant ATTESTOR_PK = 0xA11CE;
    address attestor;
    address treasury;
    address merchant;
    address buyer;
    address lp;

    uint128 constant AMOUNT = 100e6; // 100 USDC
    uint16 constant YIELD_FEE_BPS = 1000; // 10% of yield
    uint16 constant VAULT_FEE_BPS = 50; // 0.5%
    uint64 constant RESOLVE_DELAY = 60;
    uint32 constant DISPUTE_WINDOW = 14 days;

    uint256 policyId;

    function setUp() public {
        attestor = vm.addr(ATTESTOR_PK);
        treasury = makeAddr("treasury");
        merchant = makeAddr("merchant");
        buyer = makeAddr("buyer");
        lp = makeAddr("lp");

        usdc = new TestUSDC();
        registry = new PolicyRegistry();
        adapter = new MockUSYCAdapter(usdc);
        escrow = new RecourseEscrow(usdc, registry, adapter, attestor, treasury, YIELD_FEE_BPS, RESOLVE_DELAY);
        vault = new SettlementVault(usdc, escrow);
        escrow.setVault(address(vault));

        vm.prank(merchant);
        policyId = registry.registerPolicy(DISPUTE_WINDOW, 0, _rules(), "ipfs://policy");

        // Fund actors and the adapter yield buffer.
        usdc.mint(buyer, 1_000e6);
        usdc.mint(lp, 10_000e6);
        usdc.mint(address(adapter), 1_000e6);

        vm.prank(buyer);
        usdc.approve(address(escrow), type(uint256).max);
        vm.prank(lp);
        usdc.approve(address(vault), type(uint256).max);
    }

    // rule0: not-delivered, delivery attestation == NOT_DELIVERED, full refund.
    // rule1: damaged, photo required, full refund, return required.
    function _rules() internal pure returns (Rule[] memory rules) {
        rules = new Rule[](2);
        rules[0] = Rule({
            claimType: 0,
            requiredEvidenceMask: 0,
            attType: 1,
            attExpected: 2,
            claimWindow: DISPUTE_WINDOW,
            refundBps: 10000,
            requiresReturn: false
        });
        rules[1] = Rule({
            claimType: 1,
            requiredEvidenceMask: 1,
            attType: 0,
            attExpected: 0,
            claimWindow: 3 days,
            refundBps: 10000,
            requiresReturn: true
        });
    }

    function _pay() internal returns (uint256 paymentId) {
        vm.prank(buyer);
        paymentId = escrow.pay(policyId, AMOUNT, bytes32("order-1"));
    }

    function _fileNotDelivered(uint256 paymentId) internal {
        RecourseEscrow.EvidenceItem[] memory none = new RecourseEscrow.EvidenceItem[](0);
        vm.prank(buyer);
        escrow.fileDispute(paymentId, 0, none);
    }

    function _attest(uint256 paymentId, uint8 value) internal {
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 digest = escrow.attestationDigest(paymentId, 1, value, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTOR_PK, digest);
        escrow.submitAttestation(paymentId, 1, value, deadline, abi.encodePacked(r, s, v));
    }

    function test_pay_sweepsIntoAdapter() public {
        uint256 paymentId = _pay();
        RecourseEscrow.Payment memory p = escrow.getPayment(paymentId);
        assertEq(p.amount, AMOUNT);
        assertEq(uint256(p.shares), AMOUNT); // 1:1 at deploy (index == WAD)
        assertEq(uint8(p.status), uint8(RecourseEscrow.Status.Paid));
        assertEq(usdc.balanceOf(address(escrow)), 0, "escrow holds no idle USDC");
        assertEq(usdc.balanceOf(merchant), 0, "merchant not paid until settle");
    }

    function test_release_happyPath_paysBeneficiaryAndFee() public {
        uint256 paymentId = _pay();
        vm.warp(block.timestamp + 15 days);

        uint128 shares = escrow.getPayment(paymentId).shares;
        uint256 total = adapter.previewRedeem(shares);
        uint256 yieldTotal = total - AMOUNT;
        uint256 protocolFee = (yieldTotal * YIELD_FEE_BPS) / 10000;

        escrow.release(paymentId);

        assertGt(yieldTotal, 0, "yield accrued");
        assertEq(usdc.balanceOf(merchant), total - protocolFee, "merchant = principal + net yield");
        assertEq(usdc.balanceOf(treasury), protocolFee, "treasury = yield fee");
        assertEq(usdc.balanceOf(address(escrow)), 0, "no dust left in escrow");
    }

    function test_dispute_attested_fullRefund() public {
        uint256 paymentId = _pay();
        _fileNotDelivered(paymentId);
        _attest(paymentId, 2); // NOT_DELIVERED

        uint128 shares = escrow.getPayment(paymentId).shares;
        uint256 total = adapter.previewRedeem(shares);
        uint256 yieldTotal = total - AMOUNT;
        uint256 protocolFee = (yieldTotal * YIELD_FEE_BPS) / 10000;

        (, bytes32 vh) = escrow.previewVerdict(paymentId);
        vm.expectEmit(true, false, false, true, address(escrow));
        emit RecourseEscrow.Resolved(paymentId, 10000, false, 0, true, vh);
        escrow.resolve(paymentId);

        assertEq(usdc.balanceOf(buyer), 1_000e6, "buyer made whole on principal");
        assertEq(usdc.balanceOf(merchant), yieldTotal - protocolFee, "merchant keeps net yield only");
        assertEq(usdc.balanceOf(treasury), protocolFee);
        assertEq(usdc.balanceOf(address(escrow)), 0);
        assertEq(escrow.getPayment(paymentId).verdictBps, 10000);
    }

    function test_dispute_noAttestation_waitsThenDenies() public {
        uint256 paymentId = _pay();
        _fileNotDelivered(paymentId);

        // Cannot resolve an un-attested delivery dispute inside the delay window.
        vm.expectRevert(RecourseEscrow.AwaitingAttestation.selector);
        escrow.resolve(paymentId);

        vm.warp(block.timestamp + RESOLVE_DELAY + 1);
        uint128 shares = escrow.getPayment(paymentId).shares;
        uint256 total = adapter.previewRedeem(shares);
        uint256 protocolFee = ((total - AMOUNT) * YIELD_FEE_BPS) / 10000;

        escrow.resolve(paymentId);

        // rule0 needs attType 1; with none supplied, no rule matches -> default deny.
        assertEq(usdc.balanceOf(buyer), 1_000e6 - AMOUNT, "no refund");
        assertEq(usdc.balanceOf(merchant), total - protocolFee, "merchant keeps all");
        assertEq(escrow.getPayment(paymentId).verdictBps, 0);
    }

    function test_vault_advance_release_reconcile_profit() public {
        vault.enrollMerchant(merchant, VAULT_FEE_BPS, 1_000e6);
        vm.prank(lp);
        vault.deposit(1_000e6);

        uint256 paymentId = _pay();
        uint256 fee = (uint256(AMOUNT) * VAULT_FEE_BPS) / 10000;

        vault.advance(paymentId);
        assertEq(usdc.balanceOf(merchant), AMOUNT - fee, "merchant paid T+0 net of fee");
        assertEq(escrow.getPayment(paymentId).beneficiary, address(vault), "vault took the claim");
        assertEq(vault.outstanding(), AMOUNT);

        vm.warp(block.timestamp + 15 days);
        uint128 shares = escrow.getPayment(paymentId).shares;
        uint256 total = adapter.previewRedeem(shares);
        uint256 protocolFee = ((total - AMOUNT) * YIELD_FEE_BPS) / 10000;

        escrow.release(paymentId);
        vault.reconcile(paymentId);

        assertEq(vault.outstanding(), 0);
        // LP capital grew by the advance fee plus the net float yield.
        uint256 expected = 1_000e6 + fee + (total - AMOUNT - protocolFee);
        assertEq(vault.totalAssets(), expected, "share value = deposit + fee + net yield");
        assertGt(vault.totalAssets(), 1_000e6);
    }

    function test_vault_advance_fullRefund_realizesLoss() public {
        vault.enrollMerchant(merchant, VAULT_FEE_BPS, 1_000e6);
        vm.prank(lp);
        vault.deposit(1_000e6);

        uint256 paymentId = _pay();
        uint256 fee = (uint256(AMOUNT) * VAULT_FEE_BPS) / 10000;
        vault.advance(paymentId);

        _fileNotDelivered(paymentId);
        _attest(paymentId, 2);

        uint128 shares = escrow.getPayment(paymentId).shares;
        uint256 total = adapter.previewRedeem(shares);
        uint256 protocolFee = ((total - AMOUNT) * YIELD_FEE_BPS) / 10000;

        escrow.resolve(paymentId); // full refund to buyer; vault (beneficiary) recovers only net yield
        vault.reconcile(paymentId);

        assertEq(usdc.balanceOf(buyer), 1_000e6, "buyer fully refunded");
        assertEq(vault.outstanding(), 0);
        // Vault fronted (AMOUNT - fee) and recovered only net yield: a realized loss.
        uint256 expected = 1_000e6 - (AMOUNT - fee) + (total - AMOUNT - protocolFee);
        assertEq(vault.totalAssets(), expected, "share value = deposit - advanced + recovered yield");
        assertLt(vault.totalAssets(), 1_000e6, "LP realized a loss");
    }

    // Regression: depositing when the adapter index is already above 1.0 and resolving
    // immediately used to round the redeem a wei under principal and underflow the
    // refund split. The ceil-on-deposit and the clamp must keep the buyer whole.
    function test_resolve_fullRefund_shortHold_noUnderflow() public {
        vm.warp(block.timestamp + 30 days); // index well above WAD before we deposit
        uint256 paymentId = _pay();
        _fileNotDelivered(paymentId);
        _attest(paymentId, 2); // NOT_DELIVERED -> full refund, resolves immediately

        escrow.resolve(paymentId); // must not revert
        assertEq(usdc.balanceOf(buyer), 1_000e6, "buyer refunded full principal");
        assertEq(usdc.balanceOf(address(escrow)), 0, "no dust left in escrow");
    }

    function test_previewVerdict_matchesDamagedRule() public {
        uint256 paymentId = _pay();
        RecourseEscrow.EvidenceItem[] memory ev = new RecourseEscrow.EvidenceItem[](1);
        ev[0] = RecourseEscrow.EvidenceItem({evType: 1, hash: keccak256("photo")});
        vm.prank(buyer);
        escrow.fileDispute(paymentId, 1, ev); // damaged + photo

        (, bytes32 vh) = escrow.previewVerdict(paymentId);
        vm.warp(block.timestamp + RESOLVE_DELAY + 1);
        vm.expectEmit(true, false, false, true, address(escrow));
        emit RecourseEscrow.Resolved(paymentId, 10000, true, 1, true, vh);
        escrow.resolve(paymentId);
    }
}
