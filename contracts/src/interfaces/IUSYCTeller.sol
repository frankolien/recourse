// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Circle's USYC teller, the part of it we use. It is an ERC-4626 vault whose asset is
// USDC and whose share is USYC, verified on Arc testnet on 2026-09-07 at
// 0x9fdF14c5B14173D74C08Af27AebFf39240dC105A: asset() returns Arc USDC, and
// previewRedeem of one USYC agrees with the USYC/USD oracle to the last digit.
//
// Only these five are declared. The teller has the rest of the 4626 surface, but a
// smaller interface is a smaller thing to be wrong about.
interface IUSYCTeller {
    function asset() external view returns (address);

    /// USDC in, USYC minted to `receiver`. Returns shares.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// USYC in, USDC out to `receiver`, burned from `owner`. Returns assets.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /// What `shares` of USYC is worth in USDC right now.
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    /// How much USDC `owner` could actually take out, which is bounded by the fund's
    /// own cash and is far below its total assets. This is why the vault keeps a buffer.
    function maxWithdraw(address owner) external view returns (uint256 assets);
}
