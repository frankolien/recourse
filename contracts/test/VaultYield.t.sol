// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {MockUSYCAdapter} from "../src/MockUSYCAdapter.sol";
import {RecourseEscrow} from "../src/RecourseEscrow.sol";
import {SettlementVault} from "../src/SettlementVault.sol";
import {IUSYCTeller} from "../src/interfaces/IUSYCTeller.sol";
import {TestUSDC} from "./mocks/TestUSDC.sol";

/// A stand in for Circle's USYC teller that behaves the way the real one does, cash
/// shortage included. On Arc testnet the teller held 5,160 USDC against 751,910 of
/// assets, so redeeming everything at once is not a thing the vault may assume.
contract FakeTeller is IUSYCTeller {
    TestUSDC public usdcToken;
    TestUSDC public usycToken;

    /// USDC per USYC, scaled by 1e6. Starts at par and is moved by the test.
    uint256 public price = 1e6;
    /// How much USDC this teller will actually part with. Zero means no limit.
    uint256 public cashCap;
    /// USYC is a permissioned fund and its real teller refuses anyone not on its
    /// allowlist, which is what Circle's answered to us on 2026-09-12.
    bool public refuses;

    error NotPermissioned();

    constructor(TestUSDC _usdc, TestUSDC _usyc) {
        usdcToken = _usdc;
        usycToken = _usyc;
    }

    function setPrice(uint256 p) external {
        price = p;
    }

    function setCashCap(uint256 c) external {
        cashCap = c;
    }

    function setRefuses(bool r) external {
        refuses = r;
    }

    function asset() external view returns (address) {
        return address(usdcToken);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return (shares * price) / 1e6;
    }

    function maxWithdraw(address) external view returns (uint256) {
        return cashCap;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        if (refuses) revert NotPermissioned();
        usdcToken.transferFrom(msg.sender, address(this), assets);
        shares = (assets * 1e6) / price;
        usycToken.mint(receiver, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = previewRedeem(shares);
        require(cashCap == 0 || assets <= cashCap, "teller is short of cash");
        // No burn on the test token, so the shares come here instead. Same effect on
        // the vault, which is the thing under test.
        usycToken.transferFrom(owner, address(this), shares);
        usdcToken.mint(receiver, assets);
    }
}

contract VaultYieldTest is Test {
    TestUSDC usdc;
    TestUSDC usyc;
    FakeTeller teller;
    SettlementVault vault;
    RecourseEscrow escrow;

    address lp = address(0xA11CE);

    function setUp() public {
        usdc = new TestUSDC();
        usyc = new TestUSDC();
        teller = new FakeTeller(usdc, usyc);
        PolicyRegistry registry = new PolicyRegistry();
        MockUSYCAdapter adapter = new MockUSYCAdapter(usdc);
        escrow = new RecourseEscrow(usdc, registry, adapter, address(this), address(this), 0, 1 days);
        vault = new SettlementVault(usdc, escrow, IUSYCTeller(address(teller)), IERC20(address(usyc)));
        escrow.setVault(address(vault));

        usdc.mint(lp, 1_000_000e6);
        vm.prank(lp);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _deposit(uint256 amount) internal returns (uint256) {
        vm.prank(lp);
        return vault.deposit(amount);
    }

    function test_DepositPutsTheSurplusToWork() public {
        _deposit(1000e6);
        // Twenty percent stays in hand, the rest is in the fund.
        assertEq(usdc.balanceOf(address(vault)), 200e6, "cash");
        assertEq(vault.investedAssets(), 800e6, "invested");
        assertEq(vault.totalAssets(), 1000e6, "nothing lost in the move");
    }

    function test_YieldRaisesSharePriceAndNothingElse() public {
        uint256 shares = _deposit(1000e6);
        teller.setPrice(1.1e6); // the fund gained ten percent

        assertEq(vault.investedAssets(), 880e6);
        assertEq(vault.totalAssets(), 1080e6);
        assertEq(vault.convertToAssets(shares), 1080e6, "the depositor owns the gain");
    }

    function test_WithdrawSellsTheFundWhenCashIsShort() public {
        uint256 shares = _deposit(1000e6);
        uint256 before = usdc.balanceOf(lp);

        // Far more than the 200 held in cash, so the fund has to be sold.
        vm.prank(lp);
        vault.withdraw(shares / 2);

        assertEq(usdc.balanceOf(lp) - before, 500e6, "paid in full");
        assertLt(usyc.balanceOf(address(vault)), 800e6, "sold some of the fund");
        assertApproxEqAbs(vault.totalAssets(), 500e6, 2, "the rest is still there");
    }

    function test_WithdrawingEverythingEmptiesTheFund() public {
        uint256 shares = _deposit(1000e6);
        vm.prank(lp);
        uint256 out = vault.withdraw(shares);
        assertEq(out, 1000e6);
        assertEq(vault.totalAssets(), 0);
        assertEq(usyc.balanceOf(address(vault)), 0, "no dust left behind");
    }

    /// The failure that matters: the fund is short of cash. The vault must refuse
    /// rather than report a payment it could not make.
    function test_ARefusedRedeemRevertsRatherThanShortPaying() public {
        uint256 shares = _deposit(1000e6);
        teller.setCashCap(10e6);

        vm.prank(lp);
        vm.expectRevert();
        vault.withdraw(shares);

        // Nothing moved.
        assertEq(vault.sharesOf(lp), shares, "shares kept");
        assertEq(vault.totalAssets(), 1000e6, "assets kept");
    }

    function test_SmallWithdrawalIsPaidFromCashWithoutTouchingTheFund() public {
        uint256 shares = _deposit(1000e6);
        uint256 usycBefore = usyc.balanceOf(address(vault));

        vm.prank(lp);
        vault.withdraw(shares / 10); // 100, well inside the 200 buffer

        assertEq(usyc.balanceOf(address(vault)), usycBefore, "the fund was left alone");
    }

    function test_ALossIsCarriedByTheDepositorNotHidden() public {
        uint256 shares = _deposit(1000e6);
        teller.setPrice(0.9e6); // the fund fell ten percent

        assertEq(vault.investedAssets(), 720e6);
        assertEq(vault.convertToAssets(shares), 920e6, "the balance tells the truth");
    }

    function test_BufferIsTunableAndBounded() public {
        vault.setBufferBps(5000);
        _deposit(1000e6);
        assertEq(usdc.balanceOf(address(vault)), 500e6, "half in hand");

        vm.expectRevert(SettlementVault.BufferTooHigh.selector);
        vault.setBufferBps(10001);
    }

    function test_AllCashWhenThereIsNoTeller() public {
        SettlementVault plain = new SettlementVault(usdc, escrow, IUSYCTeller(address(0)), IERC20(address(0)));
        usdc.mint(lp, 100e6);
        vm.startPrank(lp);
        usdc.approve(address(plain), type(uint256).max);
        uint256 shares = plain.deposit(100e6);
        vm.stopPrank();

        assertEq(plain.investedAssets(), 0);
        assertEq(usdc.balanceOf(address(plain)), 100e6, "nothing invested");
        vm.prank(lp);
        assertEq(plain.withdraw(shares), 100e6, "and it still pays out");
    }

    /// Circle's teller answered `NotPermissioned` to this vault and to its owner alike
    /// on 2026-09-12, because USYC only admits allowlisted holders. A fund that will not
    /// take the money must not stop anyone depositing into the vault: the dollars stay
    /// as cash, which is exactly where they already were.
    function test_ARefusedInvestmentLeavesTheDepositStanding() public {
        teller.setRefuses(true);

        uint256 shares = _deposit(100e6);
        assertGt(shares, 0, "the deposit still happened");
        assertEq(usdc.balanceOf(address(vault)), 100e6, "every dollar stayed as cash");
        assertEq(vault.investedAssets(), 0, "nothing reached the fund");
        assertEq(vault.totalAssets(), 100e6, "and the balance is whole");

        // The day the fund admits us, the same call puts the surplus to work.
        teller.setRefuses(false);
        vault.invest();
        assertGt(vault.investedAssets(), 0, "now it is invested");
        assertEq(vault.totalAssets(), 100e6, "and the total did not move");
    }

    function testFuzz_DepositThenWithdrawNeverLosesMoney(uint96 amount) public {
        vm.assume(amount >= 1e6 && amount <= 100_000e6);
        usdc.mint(lp, amount);
        vm.prank(lp);
        uint256 shares = vault.deposit(amount);
        uint256 before = usdc.balanceOf(lp);
        vm.prank(lp);
        vault.withdraw(shares);
        assertApproxEqAbs(usdc.balanceOf(lp) - before, amount, 2, "out is in, give or take rounding");
    }
}
