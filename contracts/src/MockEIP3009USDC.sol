// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// A stand-in for Arc's USDC, implementing exactly the EIP-3009 surface cheques use.
///
/// It exists because Arc's USDC is a chain precompile that no local EVM can execute, so
/// the only way to prove a signed cheque actually cashes is against something that
/// enforces the same rules. The domain is deliberately identical to the real token's
/// (name "USDC", version "2"), so a cheque signed for chain 31337 here exercises the
/// same digest construction as one signed for Arc.
///
/// Not a general ERC-20. It has only what a cheque touches.
contract MockEIP3009USDC {
    string public constant name = "USDC";
    string public constant version = "2";
    uint8 public constant decimals = 6;

    mapping(address => uint256) public balanceOf;

    /// The token's replay guard, and the reason a cheque can be voided: once a nonce is
    /// true it can never be used, whether it got there by being cashed or cancelled.
    mapping(address => mapping(bytes32 => bool)) public authorizationState;

    bytes32 public immutable DOMAIN_SEPARATOR;

    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH =
        keccak256("CancelAuthorization(address authorizer,bytes32 nonce)");

    error AuthorizationNotYetValid();
    error AuthorizationExpired();
    error AuthorizationUsed();
    error InvalidSignature();
    error InsufficientBalance();

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                address(this)
            )
        );
    }

    function mint(address to, uint256 value) external {
        balanceOf[to] += value;
    }

    /// Anyone may submit. The signature is what proves `from` agreed, so the submitter
    /// pays gas and cannot alter a single term.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp <= validAfter) revert AuthorizationNotYetValid();
        if (block.timestamp >= validBefore) revert AuthorizationExpired();
        if (authorizationState[from][nonce]) revert AuthorizationUsed();

        bytes32 structHash =
            keccak256(abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce));
        _requireSigner(from, structHash, v, r, s);

        if (balanceOf[from] < value) revert InsufficientBalance();

        authorizationState[from][nonce] = true;
        balanceOf[from] -= value;
        balanceOf[to] += value;
    }

    /// Void an uncashed cheque. Only the writer can sign this, and it burns the nonce so
    /// the authorization can never be used afterwards.
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {
        if (authorizationState[authorizer][nonce]) revert AuthorizationUsed();
        bytes32 structHash = keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce));
        _requireSigner(authorizer, structHash, v, r, s);
        authorizationState[authorizer][nonce] = true;
    }

    function _requireSigner(address expected, bytes32 structHash, uint8 v, bytes32 r, bytes32 s) private view {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0) || recovered != expected) revert InvalidSignature();
    }
}
