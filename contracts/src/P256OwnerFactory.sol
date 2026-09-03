// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {P256Owner} from "./P256Owner.sol";

/// @title P256OwnerFactory
/// @notice Deploys a P256Owner per public key at an address anyone can compute first.
///
/// The address is a function of the key alone, so an account can name its Device Key
/// as a Safe owner before the contract exists, and whoever pays for the deployment
/// (Recourse, at enrolment) cannot change what gets deployed there. Deploying twice
/// is harmless: the second call returns the address that is already live.
contract P256OwnerFactory {
    /// @notice Handed to every owner as the place to retry an empty precompile answer.
    address public immutable fallbackVerifier;

    event OwnerCreated(address indexed owner, uint256 x, uint256 y);

    constructor(address fallbackVerifier_) {
        fallbackVerifier = fallbackVerifier_;
    }

    function create(uint256 x, uint256 y) external returns (address owner) {
        owner = getAddress(x, y);
        if (owner.code.length != 0) return owner;

        owner = address(new P256Owner{salt: _salt(x, y)}(x, y, fallbackVerifier));
        emit OwnerCreated(owner, x, y);
    }

    function getAddress(uint256 x, uint256 y) public view returns (address) {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(P256Owner).creationCode, abi.encode(x, y, fallbackVerifier)));
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt(x, y), initCodeHash)))));
    }

    function _salt(uint256 x, uint256 y) private pure returns (bytes32) {
        return keccak256(abi.encode(x, y));
    }
}
