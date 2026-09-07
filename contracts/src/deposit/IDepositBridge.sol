// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// The slice of CCTP v2 a deposit address uses: burn USDC here, mint it on Arc.
interface ITokenMessengerV2 {
    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        bytes calldata hookData
    ) external;
}

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

/// What a vault asks its factory for. Deliberately not baked into the vault: the
/// answers differ per chain, and a vault that carried them would have a different
/// address on every chain, which is how deposits get lost to the wrong network.
interface IDepositConfig {
    function usdc() external view returns (address);
    function messenger() external view returns (address);
    function destinationDomain() external view returns (uint32);
}
