// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// The escrow deposits principal into an adapter and redeems principal plus yield
// at settlement. MockUSYCAdapter (simulated) and USYCTellerAdapter (real) implement
// this identically, so swapping yield backends is a redeploy, not a code change.
interface IYieldAdapter {
    function deposit(uint256 assets) external returns (uint256 shares);
    function redeem(uint256 shares) external returns (uint256 assets);
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
}
