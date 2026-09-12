// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {RecourseEscrow} from "./RecourseEscrow.sol";
import {IUSYCTeller} from "./interfaces/IUSYCTeller.sol";

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

    // Where idle dollars earn. USYC is a treasury fund, so its teller holds well under
    // a percent of its assets as cash: 5,160 USDC against 751,910 on Arc testnet the
    // day this was written. Redeeming on demand at size would therefore fail, which is
    // why the vault keeps its own buffer and only invests what is above it.
    IUSYCTeller public immutable teller;
    IERC20 public immutable usyc;

    /// Share of the liquid pool held as cash rather than USYC, so an ordinary
    /// withdrawal never has to wait on the fund. Owner tunable; 20 percent to start.
    uint16 public bufferBps = 2000;

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
    error BufferTooHigh();
    error YieldNotConfigured();
    error CouldNotFreeCash();

    event BufferSet(uint16 bps);
    event Invested(uint256 assets, uint256 shares);
    event InvestRefused(uint256 assets);
    event Divested(uint256 shares, uint256 assets);

    /// `_teller` and `_usyc` may both be zero, which leaves the vault exactly as it was
    /// before yield: all cash, no fund position. That is how the tests and any chain
    /// without a teller run.
    constructor(IERC20 _usdc, RecourseEscrow _escrow, IUSYCTeller _teller, IERC20 _usyc) Ownable(msg.sender) {
        usdc = _usdc;
        escrow = _escrow;
        teller = _teller;
        usyc = _usyc;
    }

    function _cash() internal view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /// What the vault's USYC is worth in dollars, priced by the teller itself.
    function investedAssets() public view returns (uint256) {
        if (address(teller) == address(0)) return 0;
        uint256 shares = usyc.balanceOf(address(this));
        if (shares == 0) return 0;
        return teller.previewRedeem(shares);
    }

    // Cash, plus the fund position, plus advanced claims carried at par.
    function totalAssets() public view returns (uint256) {
        return _cash() + investedAssets() + outstanding;
    }

    /// Move everything above the buffer into the fund. Called after a deposit, and by
    /// the owner to top up after cash has built back up. Never touches `outstanding`,
    /// which is money already out of the door.
    function invest() public {
        if (address(teller) == address(0)) return;
        uint256 cash = _cash();
        uint256 liquid = cash + investedAssets();
        uint256 keep = (liquid * bufferBps) / 10000;
        if (cash <= keep) return;
        uint256 put = cash - keep;
        usdc.forceApprove(address(teller), put);
        uint256 before = usyc.balanceOf(address(this));
        // A fund that refuses must not take the deposit down with it. USYC is
        // permissioned: on 2026-09-12 its teller answered NotPermissioned to this vault
        // and to its owner alike, which made every LP deposit revert for a reason that
        // had nothing to do with the depositor. Refused dollars stay as cash, which is
        // exactly where they were, and the next call tries again.
        try teller.deposit(put, address(this)) {
            // Measured rather than taken from the return value, so a teller that reports
            // one number and mints another cannot move share price.
            uint256 minted = usyc.balanceOf(address(this)) - before;
            usdc.forceApprove(address(teller), 0);
            emit Invested(put, minted);
        } catch {
            usdc.forceApprove(address(teller), 0);
            emit InvestRefused(put);
        }
    }

    /// Make sure at least `need` dollars are in hand, redeeming from the fund if not.
    /// Redeems a little extra so the next small withdrawal does not pay for a redeem.
    function _freeCash(uint256 need) internal {
        uint256 cash = _cash();
        if (cash >= need) return;
        if (address(teller) == address(0)) revert InsufficientIdle();

        uint256 short = need - cash;
        uint256 shares = usyc.balanceOf(address(this));
        if (shares == 0) revert InsufficientIdle();

        // Redeem proportionally to what is short, rounded up, capped at what is held.
        uint256 held = teller.previewRedeem(shares);
        uint256 take = held == 0 ? shares : (shares * short + held - 1) / held;
        if (take > shares) take = shares;

        uint256 cashBefore = cash;
        // The teller pulls the shares, so it needs standing to take them.
        usyc.forceApprove(address(teller), take);
        teller.redeem(take, address(this), address(this));
        usyc.forceApprove(address(teller), 0);
        emit Divested(take, _cash() - cashBefore);

        // The fund is allowed to be short of cash; the vault is not allowed to pretend
        // it paid when it did not.
        if (_cash() < need) revert CouldNotFreeCash();
    }

    function setBufferBps(uint16 bps) external onlyOwner {
        if (bps > 10000) revert BufferTooHigh();
        bufferBps = bps;
        emit BufferSet(bps);
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
        invest();
    }

    function withdraw(uint256 shares) external nonReentrant returns (uint256 assetsOut) {
        if (shares == 0) revert ZeroAmount();
        if (shares > sharesOf[msg.sender]) revert InsufficientShares();

        assetsOut = (shares * totalAssets()) / totalShares;
        // Capital tied up in outstanding advances cannot be withdrawn; the fund
        // position can be, so it is sold before the balance is called short.
        if (assetsOut > _cash() + investedAssets()) revert InsufficientIdle();
        _freeCash(assetsOut);

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

        _freeCash(net);
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
