// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Rule, CLAIM_PARTIAL_FAILURE, EV_CALL_LOG_ROOT, ATT_SLA_OUTCOME, SLA_SEVERE, SLA_CLEAN} from "../src/Types.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {MockUSYCAdapter} from "../src/MockUSYCAdapter.sol";
import {RecourseEscrow} from "../src/RecourseEscrow.sol";
import {TestUSDC} from "./mocks/TestUSDC.sol";

// The three contract changes from docs/agent-settlement.md section 6, each tested
// through the attack it exists to stop rather than only its happy path:
//
//   I8  a merchant cannot attest against its own dispute
//   I6  an attestation is only valid from the attestor that policy names
//   I7  a relayer can submit a payment but cannot become the buyer or redirect it
contract AgentEscrowTest is Test {
    TestUSDC usdc;
    PolicyRegistry registry;
    MockUSYCAdapter adapter;
    RecourseEscrow escrow;

    uint256 constant GLOBAL_ATTESTOR_PK = 0xA11CE;
    uint256 constant POLICY_ATTESTOR_PK = 0xB0B;
    uint256 constant BUYER_PK = 0xBEEF;

    address globalAttestor;
    address policyAttestor;
    address buyer;
    address merchant;
    address relayer;

    uint128 constant AMOUNT = 25e6;
    uint32 constant WINDOW = 1 hours;

    uint256 policyId;

    function setUp() public {
        globalAttestor = vm.addr(GLOBAL_ATTESTOR_PK);
        policyAttestor = vm.addr(POLICY_ATTESTOR_PK);
        buyer = vm.addr(BUYER_PK);
        merchant = makeAddr("merchant");
        relayer = makeAddr("relayer");

        usdc = new TestUSDC();
        registry = new PolicyRegistry();
        adapter = new MockUSYCAdapter(usdc);
        escrow = new RecourseEscrow(usdc, registry, adapter, globalAttestor, makeAddr("treasury"), 1000, 60);

        vm.prank(merchant);
        policyId = registry.registerPolicy(WINDOW, 5000, _ladder(), "ipfs://agent");

        usdc.mint(buyer, 10_000e6);
        vm.prank(buyer);
        usdc.approve(address(escrow), type(uint256).max);
        usdc.mint(address(adapter), 1_000e6);
    }

    // One rung of the severity ladder is enough to prove attestation routing.
    function _ladder() internal pure returns (Rule[] memory rules) {
        rules = new Rule[](1);
        rules[0] = Rule({
            claimType: CLAIM_PARTIAL_FAILURE,
            requiredEvidenceMask: EV_CALL_LOG_ROOT,
            attType: ATT_SLA_OUTCOME,
            attExpected: SLA_SEVERE,
            claimWindow: WINDOW,
            refundBps: 5000,
            requiresReturn: false
        });
    }

    function _pay() internal returns (uint256 paymentId) {
        vm.prank(buyer);
        paymentId = escrow.pay(policyId, AMOUNT, keccak256("session"));
    }

    function _fileSevere(uint256 paymentId) internal {
        RecourseEscrow.EvidenceItem[] memory items = new RecourseEscrow.EvidenceItem[](1);
        items[0] = RecourseEscrow.EvidenceItem({evType: EV_CALL_LOG_ROOT, hash: keccak256("log")});
        vm.prank(buyer);
        escrow.fileDispute(paymentId, CLAIM_PARTIAL_FAILURE, items);
    }

    function _attest(uint256 pk, uint256 paymentId, uint8 value) internal view returns (bytes memory) {
        bytes32 digest = escrow.attestationDigest(paymentId, ATT_SLA_OUTCOME, value, uint64(block.timestamp + 1 days));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    // I8 ------------------------------------------------------------------

    function test_merchantCannotNameItselfAsAttestor() public {
        vm.prank(merchant);
        vm.expectRevert(RecourseEscrow.AttestorIsMerchant.selector);
        escrow.setPolicyAttestor(policyId, merchant);
    }

    function test_attestorCannotBeZeroOrSetTwiceOrSetByAnyoneElse() public {
        vm.prank(merchant);
        vm.expectRevert(RecourseEscrow.AttestorIsMerchant.selector);
        escrow.setPolicyAttestor(policyId, address(0));

        vm.prank(relayer);
        vm.expectRevert(RecourseEscrow.NotPolicyMerchant.selector);
        escrow.setPolicyAttestor(policyId, policyAttestor);

        vm.prank(merchant);
        escrow.setPolicyAttestor(policyId, policyAttestor);

        // Immutable after the first set, so a buyer that checked before paying
        // cannot have the attestor swapped underneath its payment.
        vm.prank(merchant);
        vm.expectRevert(RecourseEscrow.AttestorAlreadySet.selector);
        escrow.setPolicyAttestor(policyId, makeAddr("someone else"));
    }

    function test_attestorFallsBackToGlobalUntilNamed() public {
        assertEq(escrow.attestorFor(policyId), globalAttestor);
        vm.prank(merchant);
        escrow.setPolicyAttestor(policyId, policyAttestor);
        assertEq(escrow.attestorFor(policyId), policyAttestor);
    }

    function test_agreementHashCoversTheAttestorAsWellAsTheRules() public {
        bytes32 before = escrow.agreementHash(policyId);
        vm.prank(merchant);
        escrow.setPolicyAttestor(policyId, policyAttestor);
        bytes32 afterSet = escrow.agreementHash(policyId);

        assertTrue(before != afterSet, "naming an attestor must change the agreement");
        assertEq(afterSet, keccak256(abi.encode(registry.policyHash(policyId), policyAttestor)));
    }

    // I6 ------------------------------------------------------------------

    function test_namedAttestorSignatureIsAccepted() public {
        vm.prank(merchant);
        escrow.setPolicyAttestor(policyId, policyAttestor);

        uint256 paymentId = _pay();
        _fileSevere(paymentId);
        escrow.submitAttestation(
            paymentId, ATT_SLA_OUTCOME, SLA_SEVERE, uint64(block.timestamp + 1 days), _attest(POLICY_ATTESTOR_PK, paymentId, SLA_SEVERE)
        );

        assertEq(escrow.getPayment(paymentId).attValue, SLA_SEVERE);
    }

    // Once a policy names its own attestor the global one loses authority over it,
    // otherwise the protocol operator could settle any agent dispute it liked.
    function test_globalAttestorLosesAuthorityOverANamedPolicy() public {
        vm.prank(merchant);
        escrow.setPolicyAttestor(policyId, policyAttestor);

        uint256 paymentId = _pay();
        _fileSevere(paymentId);

        // Built before expectRevert is armed: _attest calls the escrow to fetch the
        // digest, and expectRevert binds to the next call whichever one that is.
        uint64 deadline = uint64(block.timestamp + 1 days);
        bytes memory sig = _attest(GLOBAL_ATTESTOR_PK, paymentId, SLA_CLEAN);

        vm.expectRevert(RecourseEscrow.BadAttestor.selector);
        escrow.submitAttestation(paymentId, ATT_SLA_OUTCOME, SLA_CLEAN, deadline, sig);
    }

    // I7 ------------------------------------------------------------------

    function _authorize(uint256 pid, bytes32 orderRef, uint128 amount)
        internal
        view
        returns (bytes32 nonce, uint8 v, bytes32 r, bytes32 s)
    {
        nonce = escrow.authorizationNonce(pid, orderRef, buyer);
        bytes32 structHash = keccak256(
            abi.encode(
                usdc.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
                buyer,
                address(escrow),
                uint256(amount),
                uint256(0),
                uint256(block.timestamp + 1 hours),
                nonce
            )
        );
        (v, r, s) = vm.sign(BUYER_PK, keccak256(abi.encodePacked("\x19\x01", usdc.DOMAIN_SEPARATOR(), structHash)));
    }

    function test_relayerSubmitsButTheSignerIsTheBuyer() public {
        bytes32 orderRef = keccak256("session-a");
        (bytes32 nonce, uint8 v, bytes32 r, bytes32 s) = _authorize(policyId, orderRef, AMOUNT);

        uint256 buyerBefore = usdc.balanceOf(buyer);

        vm.prank(relayer);
        uint256 paymentId =
            escrow.payWithAuthorization(policyId, AMOUNT, orderRef, buyer, 0, block.timestamp + 1 hours, nonce, v, r, s);

        RecourseEscrow.Payment memory pmt = escrow.getPayment(paymentId);
        assertEq(pmt.buyer, buyer, "the signer must be the buyer, not the submitter");
        assertEq(usdc.balanceOf(buyer), buyerBefore - AMOUNT, "funds came from the signer");
        assertEq(usdc.balanceOf(relayer), 0, "the relayer paid nothing");
    }

    // The whole reason payWithAuthorization exists: a relayer-submitted payment must
    // still refund the person who actually paid.
    function test_relayerSubmittedPaymentRefundsTheBuyerNotTheRelayer() public {
        vm.prank(merchant);
        escrow.setPolicyAttestor(policyId, policyAttestor);

        bytes32 orderRef = keccak256("session-b");
        (bytes32 nonce, uint8 v, bytes32 r, bytes32 s) = _authorize(policyId, orderRef, AMOUNT);
        vm.prank(relayer);
        uint256 paymentId =
            escrow.payWithAuthorization(policyId, AMOUNT, orderRef, buyer, 0, block.timestamp + 1 hours, nonce, v, r, s);

        _fileSevere(paymentId);
        escrow.submitAttestation(
            paymentId, ATT_SLA_OUTCOME, SLA_SEVERE, uint64(block.timestamp + 1 days), _attest(POLICY_ATTESTOR_PK, paymentId, SLA_SEVERE)
        );

        uint256 buyerBefore = usdc.balanceOf(buyer);
        escrow.resolve(paymentId);

        assertEq(usdc.balanceOf(buyer), buyerBefore + AMOUNT / 2, "50% ladder rung goes to the signer");
        assertEq(usdc.balanceOf(relayer), 0);
    }

    // Pinned against the TypeScript client's authorizationNonce for the same inputs.
    // The buyer derives this off chain and the escrow recomputes it, so a divergence
    // between the two is invisible in either suite alone and rejects every relayed
    // payment with BadNonce.
    function test_authorizationNonceMatchesTheClientDerivation() public view {
        assertEq(
            escrow.authorizationNonce(
                42, 0x5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e, address(0xB1)
            ),
            0xc0add9bcb03087e86c24fe2da04f94753ef5485be83c6244cee0c7ccb6451c5a
        );
    }

    function test_authorizationCannotBeRedirectedToAnotherPolicy() public {
        vm.prank(merchant);
        uint256 otherPolicy = registry.registerPolicy(WINDOW, 0, _ladder(), "ipfs://other");

        bytes32 orderRef = keccak256("session-c");
        (bytes32 nonce, uint8 v, bytes32 r, bytes32 s) = _authorize(policyId, orderRef, AMOUNT);

        // Same signature, aimed at a policy the buyer never agreed to.
        vm.prank(relayer);
        vm.expectRevert(RecourseEscrow.BadNonce.selector);
        escrow.payWithAuthorization(otherPolicy, AMOUNT, orderRef, buyer, 0, block.timestamp + 1 hours, nonce, v, r, s);
    }

    function test_authorizationCannotBeRedirectedToAnotherOrder() public {
        bytes32 orderRef = keccak256("session-d");
        (bytes32 nonce, uint8 v, bytes32 r, bytes32 s) = _authorize(policyId, orderRef, AMOUNT);

        vm.prank(relayer);
        vm.expectRevert(RecourseEscrow.BadNonce.selector);
        escrow.payWithAuthorization(
            policyId, AMOUNT, keccak256("a different session"), buyer, 0, block.timestamp + 1 hours, nonce, v, r, s
        );
    }

    function test_authorizationCannotBeReplayed() public {
        bytes32 orderRef = keccak256("session-e");
        (bytes32 nonce, uint8 v, bytes32 r, bytes32 s) = _authorize(policyId, orderRef, AMOUNT);

        vm.prank(relayer);
        escrow.payWithAuthorization(policyId, AMOUNT, orderRef, buyer, 0, block.timestamp + 1 hours, nonce, v, r, s);

        // The token consumed the nonce, so the second submission cannot spend it.
        vm.prank(relayer);
        vm.expectRevert(TestUSDC.AuthorizationUsed.selector);
        escrow.payWithAuthorization(policyId, AMOUNT, orderRef, buyer, 0, block.timestamp + 1 hours, nonce, v, r, s);
    }
}
