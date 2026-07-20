// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldAdapter} from "./interfaces/IYieldAdapter.sol";

// Simulated USYC: a share price that accrues linearly at a fixed APY from deploy,
// deterministic per block timestamp. It stands in behind IYieldAdapter until the
// real Teller is wired; swapping to USYCTellerAdapter is a redeploy.
//
// Yield is paid from the adapter's own USDC balance, so it must be pre-funded with
// a buffer above deposited principal (the deploy script and tests fund it). The real
// Teller has its own yield source and needs no buffer.
contract MockUSYCAdapter is IYieldAdapter {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    uint256 public immutable startTime;

    uint256 private constant WAD = 1e18;
    uint256 private constant APY_BPS = 450; // 4.5%
    uint256 private constant YEAR = 365 days;

    // Escrow is the only expected caller, but shares are tracked per holder so a
    // stranger cannot redeem shares they never minted and drain the buffer.
    mapping(address => uint256) public sharesOf;

    constructor(IERC20 _usdc) {
        usdc = _usdc;
        startTime = block.timestamp;
    }

    // Share price scaled by WAD; 1.0 at deploy, rising with elapsed time.
    function index() public view returns (uint256) {
        return WAD + (WAD * APY_BPS * (block.timestamp - startTime)) / (10000 * YEAR);
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        usdc.safeTransferFrom(msg.sender, address(this), assets);
        // Round shares up so redeem never returns less than the deposited principal.
        // A floor at both deposit and redeem can lose a wei on a short hold, which
        // would underflow the escrow's refund split. The extra wei is covered by the
        // adapter's yield buffer.
        uint256 idx = index();
        shares = (assets * WAD + idx - 1) / idx;
        sharesOf[msg.sender] += shares;
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return (shares * index()) / WAD;
    }

    function redeem(uint256 shares) external returns (uint256 assets) {
        require(sharesOf[msg.sender] >= shares, "insufficient shares");
        sharesOf[msg.sender] -= shares;
        assets = previewRedeem(shares);
        usdc.safeTransfer(msg.sender, assets);
    }
}
