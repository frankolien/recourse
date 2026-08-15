// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// The subset of EIP-3009 the escrow needs. Verified present on Arc testnet USDC
// (0x3600...0000, proxy to 0xc6ad664a...) by selector inspection of the
// implementation bytecode, alongside transferWithAuthorization, cancelAuthorization
// and EIP-2612 permit.
//
// receiveWithAuthorization rather than transferWithAuthorization is what makes this
// safe to accept from a relayer: the token requires msg.sender == to, so only the
// escrow can spend an authorization made out to the escrow, and `from` is proven by
// the payer's own signature rather than taken from msg.sender.
interface IERC3009 {
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);
}
