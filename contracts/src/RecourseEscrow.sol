// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Policy, VerdictInput, Verdict} from "./Types.sol";
import {PolicyEngine} from "./PolicyEngine.sol";
import {PolicyRegistry} from "./PolicyRegistry.sol";
import {IYieldAdapter} from "./interfaces/IYieldAdapter.sol";

// Per-payment escrow pinned to an immutable policy. Principal sweeps into the yield
// adapter on pay and is redeemed at settlement. Disputes resolve deterministically
// through PolicyEngine; the attestor only signs objective facts and never decides
// outcomes. All USDC amounts are 6-decimal ERC-20 units (never native).
contract RecourseEscrow is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Status {
        None,
        Paid,
        Disputed,
        Settled
    }

    struct Payment {
        address buyer; // refundTo, fixed at pay time
        address merchant;
        address beneficiary; // merchant, or vault after assignment
        uint256 policyId;
        uint128 amount; // USDC, 6 decimals
        uint128 shares; // yield adapter shares
        uint64 paidAt;
        uint64 filedAt;
        uint8 claimType;
        uint16 evidenceMask;
        uint8 attType;
        uint8 attValue; // 0 until attested
        bytes32 evidenceRoot;
        uint16 verdictBps;
        Status status;
    }

    struct EvidenceItem {
        uint8 evType; // PHOTO 1, DESCRIPTION 2, TRACKING_REF 4, VIDEO 8
        bytes32 hash;
    }

    IERC20 public immutable usdc;
    PolicyRegistry public immutable registry;
    IYieldAdapter public immutable adapter;

    address public attestor; // signs delivery attestations
    address public treasury; // collects the yield fee
    address public vault; // the trusted settlement vault permitted to take assignment
    uint16 public immutable yieldFeeBps; // protocol cut of yield at settlement
    uint64 public immutable resolveDelay; // min wait before resolving an un-attested dispute

    uint256 public paymentCount;
    mapping(uint256 => Payment) private _payments;

    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant ATTESTATION_TYPEHASH =
        keccak256("Attestation(uint256 paymentId,uint8 attType,uint8 value,uint64 deadline)");
    bytes32 public immutable DOMAIN_SEPARATOR;

    event Paid(
        uint256 indexed paymentId,
        address indexed buyer,
        address indexed merchant,
        uint256 policyId,
        uint128 amount,
        bytes32 orderRef,
        bytes32 policyHash
    );
    event DisputeFiled(uint256 indexed paymentId, uint8 claimType, uint16 evidenceMask, bytes32 evidenceRoot);
    event Attested(uint256 indexed paymentId, uint8 attType, uint8 value);
    event Resolved(
        uint256 indexed paymentId, uint16 refundBps, bool requiresReturn, uint8 ruleIndex, bool matched, bytes32 verdictHash
    );
    event Released(uint256 indexed paymentId, uint128 principal, uint128 paidToBeneficiary);
    event Assigned(uint256 indexed paymentId, address indexed newBeneficiary);

    error BadPolicy();
    error NotBuyer();
    error NotOpen();
    error WindowClosed();
    error WindowOpen();
    error NotDisputed();
    error AwaitingAttestation();
    error AttestationExpired();
    error BadAttestor();
    error OnlyVault();
    error ClaimClosed();

    constructor(
        IERC20 _usdc,
        PolicyRegistry _registry,
        IYieldAdapter _adapter,
        address _attestor,
        address _treasury,
        uint16 _yieldFeeBps,
        uint64 _resolveDelay
    ) Ownable(msg.sender) {
        usdc = _usdc;
        registry = _registry;
        adapter = _adapter;
        attestor = _attestor;
        treasury = _treasury;
        yieldFeeBps = _yieldFeeBps;
        resolveDelay = _resolveDelay;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, keccak256("RecourseAttestor"), keccak256("1"), block.chainid, address(this))
        );
    }

    function setAttestor(address a) external onlyOwner {
        attestor = a;
    }

    function setTreasury(address t) external onlyOwner {
        treasury = t;
    }

    function setVault(address v) external onlyOwner {
        vault = v;
    }

    function pay(uint256 policyId, uint128 amount, bytes32 orderRef) external nonReentrant returns (uint256 paymentId) {
        require(amount > 0, "zero amount");
        Policy memory p = registry.getPolicy(policyId);
        if (p.merchant == address(0)) revert BadPolicy();

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        usdc.forceApprove(address(adapter), amount);
        uint256 shares = adapter.deposit(amount);

        paymentId = ++paymentCount;
        Payment storage pmt = _payments[paymentId];
        pmt.buyer = msg.sender;
        pmt.merchant = p.merchant;
        pmt.beneficiary = p.merchant;
        pmt.policyId = policyId;
        pmt.amount = amount;
        pmt.shares = uint128(shares);
        pmt.paidAt = uint64(block.timestamp);
        pmt.status = Status.Paid;

        emit Paid(paymentId, msg.sender, p.merchant, policyId, amount, orderRef, registry.policyHash(policyId));
    }

    function fileDispute(uint256 paymentId, uint8 claimType, EvidenceItem[] calldata evidence) external {
        Payment storage pmt = _payments[paymentId];
        if (msg.sender != pmt.buyer) revert NotBuyer();
        if (pmt.status != Status.Paid) revert NotOpen();

        Policy memory p = registry.getPolicy(pmt.policyId);
        if (block.timestamp > uint256(pmt.paidAt) + p.disputeWindow) revert WindowClosed();

        uint16 mask;
        bytes32 root;
        for (uint256 k = 0; k < evidence.length; k++) {
            mask |= evidence[k].evType;
            root = keccak256(abi.encodePacked(root, evidence[k].evType, evidence[k].hash));
        }

        pmt.claimType = claimType;
        pmt.evidenceMask = mask;
        pmt.evidenceRoot = root;
        pmt.filedAt = uint64(block.timestamp);
        pmt.status = Status.Disputed;

        emit DisputeFiled(paymentId, claimType, mask, root);
    }

    function submitAttestation(uint256 paymentId, uint8 attType, uint8 value, uint64 deadline, bytes calldata sig)
        external
    {
        Payment storage pmt = _payments[paymentId];
        if (pmt.status != Status.Disputed) revert NotDisputed();
        if (block.timestamp > deadline) revert AttestationExpired();

        bytes32 digest = attestationDigest(paymentId, attType, value, deadline);
        address signer = _recover(digest, sig);
        if (signer == address(0) || signer != attestor) revert BadAttestor();

        pmt.attType = attType;
        pmt.attValue = value;
        emit Attested(paymentId, attType, value);
    }

    function resolve(uint256 paymentId) external nonReentrant {
        Payment storage pmt = _payments[paymentId];
        if (pmt.status != Status.Disputed) revert NotDisputed();
        // Attestation-dependent rules must not resolve before the attestor has had a
        // chance to sign; un-attested disputes wait out resolveDelay then fall through.
        if (pmt.attType == 0 && block.timestamp < uint256(pmt.filedAt) + resolveDelay) revert AwaitingAttestation();

        Policy memory p = registry.getPolicy(pmt.policyId);
        VerdictInput memory input = _inputOf(pmt);
        Verdict memory v = PolicyEngine.compute(p, input);

        pmt.verdictBps = v.refundBps;
        pmt.status = Status.Settled;

        uint256 total = adapter.redeem(pmt.shares);
        uint256 refund = (uint256(pmt.amount) * v.refundBps) / 10000;
        // Never distribute more than was redeemed; clamps guard against adapter rounding
        // so a settlement can round a wei short but never revert.
        if (refund > total) refund = total;
        uint256 yieldTotal = total > pmt.amount ? total - pmt.amount : 0;
        uint256 protocolFee = (yieldTotal * yieldFeeBps) / 10000;
        uint256 rest = total - refund;
        if (protocolFee > rest) protocolFee = rest;
        // Residual to the beneficiary guarantees buyer + protocol + beneficiary == total.
        uint256 toBeneficiary = rest - protocolFee;

        if (refund > 0) usdc.safeTransfer(pmt.buyer, refund);
        if (protocolFee > 0) usdc.safeTransfer(treasury, protocolFee);
        if (toBeneficiary > 0) usdc.safeTransfer(pmt.beneficiary, toBeneficiary);

        bytes32 vh = PolicyEngine.verdictHash(registry.policyHash(pmt.policyId), paymentId, input, v);
        emit Resolved(paymentId, v.refundBps, v.requiresReturn, v.ruleIndex, v.matched, vh);
    }

    function release(uint256 paymentId) external nonReentrant {
        Payment storage pmt = _payments[paymentId];
        if (pmt.status != Status.Paid) revert NotOpen();

        Policy memory p = registry.getPolicy(pmt.policyId);
        if (block.timestamp <= uint256(pmt.paidAt) + p.disputeWindow) revert WindowOpen();

        pmt.status = Status.Settled;

        uint256 total = adapter.redeem(pmt.shares);
        uint256 yieldTotal = total > pmt.amount ? total - pmt.amount : 0;
        uint256 protocolFee = (yieldTotal * yieldFeeBps) / 10000;
        uint256 toBeneficiary = total - protocolFee;

        if (protocolFee > 0) usdc.safeTransfer(treasury, protocolFee);
        usdc.safeTransfer(pmt.beneficiary, toBeneficiary);

        emit Released(paymentId, pmt.amount, uint128(toBeneficiary));
    }

    // Called by the settlement vault after it advances the merchant, to take over the
    // escrow claim. Gated to the configured vault: the vault pays the merchant net and
    // checks enrollment and caps before calling, so the merchant is never harmed.
    function assign(uint256 paymentId, address newBeneficiary) external {
        if (msg.sender != vault) revert OnlyVault();
        Payment storage pmt = _payments[paymentId];
        if (pmt.status != Status.Paid && pmt.status != Status.Disputed) revert ClaimClosed();
        pmt.beneficiary = newBeneficiary;
        emit Assigned(paymentId, newBeneficiary);
    }

    function previewVerdict(uint256 paymentId) external view returns (Verdict memory v, bytes32 verdictHash) {
        Payment storage pmt = _payments[paymentId];
        Policy memory p = registry.getPolicy(pmt.policyId);
        VerdictInput memory input = _inputOf(pmt);
        v = PolicyEngine.compute(p, input);
        verdictHash = PolicyEngine.verdictHash(registry.policyHash(pmt.policyId), paymentId, input, v);
    }

    function getPayment(uint256 paymentId) external view returns (Payment memory) {
        return _payments[paymentId];
    }

    function attestationDigest(uint256 paymentId, uint8 attType, uint8 value, uint64 deadline)
        public
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(ATTESTATION_TYPEHASH, paymentId, attType, value, deadline));
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    function _inputOf(Payment storage pmt) private view returns (VerdictInput memory) {
        return VerdictInput({
            claimType: pmt.claimType,
            evidenceMask: pmt.evidenceMask,
            attType: pmt.attType,
            attValue: pmt.attValue,
            paidAt: pmt.paidAt,
            filedAt: pmt.filedAt
        });
    }

    function _recover(bytes32 digest, bytes calldata sig) private pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        // Reject the upper range of s to block signature malleability.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }
        return ecrecover(digest, v, r, s);
    }
}
