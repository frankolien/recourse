// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title P256Owner
/// @notice A Safe owner that is a P-256 public key.
///
/// A Safe can only hold addresses as owners, and the Device Key in a Recourse account
/// lives in the phone's Secure Enclave, which speaks P-256 rather than secp256k1. This
/// contract stands in for that key: it is deployed at an address derived from the
/// public key, and the Safe asks it, through EIP-1271, whether a signature is the
/// key's. It holds no funds and has no other authority.
///
/// Verification goes to the RIP-7212 precompile at 0x100 first, which Arc ships. The
/// precompile answers an invalid signature with empty return data, exactly as it
/// would if it did not exist, so an empty answer is retried against a Solidity
/// verifier (Daimo's, which speaks the same ABI) before being called invalid. A chain
/// without the precompile pays that fallback on every check; a chain with it pays it
/// only for signatures that were wrong anyway.
contract P256Owner {
    /// @dev EIP-1271 for a 32-byte hash.
    bytes4 private constant MAGIC_HASH = 0x1626ba7e;
    /// @dev The older EIP-1271 shape, over the pre-image. Safe 1.4.1 uses this one for
    ///      contract owners, handing over the full transaction or message bytes.
    bytes4 private constant MAGIC_BYTES = 0x20c13b0b;
    bytes4 private constant NOT_VALID = 0xffffffff;

    address private constant PRECOMPILE = address(0x100);

    /// @notice The affine public key this owner answers for.
    uint256 public immutable x;
    uint256 public immutable y;

    /// @notice Where an empty precompile answer is retried. Same ABI as the precompile.
    address public immutable fallbackVerifier;

    error BadSignatureLength(uint256 length);

    constructor(uint256 x_, uint256 y_, address fallbackVerifier_) {
        x = x_;
        y = y_;
        fallbackVerifier = fallbackVerifier_;
    }

    /// @notice EIP-1271 over a hash. `signature` is `r || s`, 64 bytes, no recovery id.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        return _verify(hash, signature) ? MAGIC_HASH : NOT_VALID;
    }

    /// @notice EIP-1271 over the bytes the signature covers. The Secure Enclave signs
    ///         the keccak of exactly these bytes.
    function isValidSignature(bytes calldata data, bytes calldata signature) external view returns (bytes4) {
        return _verify(keccak256(data), signature) ? MAGIC_BYTES : NOT_VALID;
    }

    function _verify(bytes32 hash, bytes calldata signature) internal view returns (bool) {
        if (signature.length != 64) revert BadSignatureLength(signature.length);
        bytes memory input = abi.encodePacked(hash, signature, x, y);

        (bool ok, bytes memory answer) = PRECOMPILE.staticcall(input);
        if (ok && answer.length == 32) {
            return abi.decode(answer, (uint256)) == 1;
        }
        if (fallbackVerifier == address(0)) return false;

        (ok, answer) = fallbackVerifier.staticcall(input);
        return ok && answer.length == 32 && abi.decode(answer, (uint256)) == 1;
    }
}
