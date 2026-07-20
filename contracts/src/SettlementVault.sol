// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {RecourseEscrow} from "./RecourseEscrow.sol";

// USDC liquidity pool that fronts merchants at T+0. On advance it pays the merchant
// net of fee and takes assignment of the escrow claim; at settlement the claim pays
// the vault back. LP return = advance fees + USYC float yield - refund losses.
//
// Minimal ERC-4626 shape: share accounting only, no transferable share token.
// totalAssets carries advanced claims at par (outstanding) until reconcile realizes
// the actual settled amount into share price. Inflation-attack hardening is omitted
// (testnet, trusted LPs); the deck lists it as production work.
contract SettlementVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    RecourseEscrow public immutable escrow;

    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    // Sum of advanced claims booked at par, not yet reconciled.
    uint256 public outstanding;

    struct MerchantTerms {
        bool enrolled;
        uint16 feeBps;
        uint128 exposureCap;
        uint128 exposure; // outstanding par advanced to this merchant
    }

    mapping(address => MerchantTerms) public merchants;

    struct AdvanceInfo {
        address merchant;
        uint128 amount;
        bool exists;
        bool reconciled;
    }

    mapping(uint256 => AdvanceInfo) public advances;

    event Deposited(address indexed lp, uint256 assets, uint256 shares);
    event Withdrawn(address indexed lp, uint256 shares, uint256 assets);
    event MerchantEnrolled(address indexed merchant, uint16 feeBps, uint128 exposureCap);
    event Advanced(uint256 indexed paymentId, address indexed merchant, uint128 amount, uint256 fee);
    event Reconciled(uint256 indexed paymentId, uint128 amount);

    error ZeroAmount();
    error ZeroShares();
    error InsufficientShares();
    error InsufficientIdle();
    error FeeTooHigh();
    error NotEnrolled();
    error PaymentNotOpen();
    error AlreadyAssigned();
    error AlreadyAdvanced();
    error ExposureCapExceeded();
    error UnknownAdvance();
    error NotSettled();
    error NotOurClaim();

    constructor(IERC20 _usdc, RecourseEscrow _escrow) Ownable(msg.sender) {
        usdc = _usdc;
        escrow = _escrow;
    }

    // Idle USDC plus advanced claims carried at par.
    function totalAssets() public view returns (uint256) {
        return usdc.balanceOf(address(this)) + outstanding;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return totalShares == 0 ? shares : (shares * totalAssets()) / totalShares;
    }

    function deposit(uint256 assets) external nonReentrant returns (uint256 minted) {
        if (assets == 0) revert ZeroAmount();
        // Price against assets held before this deposit is pulled in.
        uint256 supply = totalShares;
        uint256 assetsBefore = totalAssets();
        usdc.safeTransferFrom(msg.sender, address(this), assets);

        minted = supply == 0 ? assets : (assets * supply) / assetsBefore;
        if (minted == 0) revert ZeroShares();

        totalShares = supply + minted;
        sharesOf[msg.sender] += minted;
        emit Deposited(msg.sender, assets, minted);
    }

    function withdraw(uint256 shares) external nonReentrant returns (uint256 assetsOut) {
        if (shares == 0) revert ZeroAmount();
        if (shares > sharesOf[msg.sender]) revert InsufficientShares();

        assetsOut = (shares * totalAssets()) / totalShares;
        // Capital tied up in outstanding advances cannot be withdrawn.
        if (assetsOut > usdc.balanceOf(address(this))) revert InsufficientIdle();

        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
        usdc.safeTransfer(msg.sender, assetsOut);
        emit Withdrawn(msg.sender, shares, assetsOut);
    }

    function enrollMerchant(address merchant, uint16 feeBps, uint128 exposureCap) external onlyOwner {
        if (feeBps > 10000) revert FeeTooHigh();
        MerchantTerms storage m = merchants[merchant];
        m.enrolled = true;
        m.feeBps = feeBps;
        m.exposureCap = exposureCap;
        emit MerchantEnrolled(merchant, feeBps, exposureCap);
    }

    function advance(uint256 paymentId) external nonReentrant {
        RecourseEscrow.Payment memory pmt = escrow.getPayment(paymentId);
        if (pmt.status != RecourseEscrow.Status.Paid) revert PaymentNotOpen();
        if (pmt.beneficiary != pmt.merchant) revert AlreadyAssigned();
        if (advances[paymentId].exists) revert AlreadyAdvanced();

        MerchantTerms storage m = merchants[pmt.merchant];
        if (!m.enrolled) revert NotEnrolled();
        if (uint256(m.exposure) + pmt.amount > m.exposureCap) revert ExposureCapExceeded();

        uint256 fee = (uint256(pmt.amount) * m.feeBps) / 10000;
        uint256 net = pmt.amount - fee;

        m.exposure += pmt.amount;
        outstanding += pmt.amount;
        advances[paymentId] = AdvanceInfo({merchant: pmt.merchant, amount: pmt.amount, exists: true, reconciled: false});

        usdc.safeTransfer(pmt.merchant, net);
        escrow.assign(paymentId, address(this));
        emit Advanced(paymentId, pmt.merchant, pmt.amount, fee);
    }

    // Settle the books after the escrow paid this vault as beneficiary. The received
    // USDC already sits in idle balance; removing the par from outstanding lets the
    // realized gain or loss flow into share price.
    function reconcile(uint256 paymentId) external nonReentrant {
        AdvanceInfo storage a = advances[paymentId];
        if (!a.exists || a.reconciled) revert UnknownAdvance();

        RecourseEscrow.Payment memory pmt = escrow.getPayment(paymentId);
        if (pmt.status != RecourseEscrow.Status.Settled) revert NotSettled();
        if (pmt.beneficiary != address(this)) revert NotOurClaim();

        a.reconciled = true;
        outstanding -= a.amount;
        merchants[a.merchant].exposure -= a.amount;
        emit Reconciled(paymentId, a.amount);
    }
}
