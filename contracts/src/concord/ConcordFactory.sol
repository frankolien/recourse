// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {Concord} from "./Concord.sol";
import {ConcordProxy} from "./ConcordProxy.sol";
import {Init} from "./IConcord.sol";

/// @title ConcordFactory
/// @notice Deploys accounts at addresses anyone can compute from the first signer set
///         and a salt, so money can arrive before the account exists and can only ever
///         be controlled by those signers. Also serves as an ERC-4337 `initCode` target.
contract ConcordFactory {
    address public immutable implementation;

    event AccountCreated(address indexed account, bytes32 salt);

    constructor(address implementation_) {
        implementation = implementation_;
    }

    function createAccount(Init calldata init, bytes32 salt) external returns (address account) {
        bytes memory code = _creationCode(init);
        account = Create2.computeAddress(salt, keccak256(code));
        if (account.code.length != 0) return account;
        account = Create2.deploy(0, salt, code);
        emit AccountCreated(account, salt);
    }

    function getAddress(Init calldata init, bytes32 salt) external view returns (address) {
        return Create2.computeAddress(salt, keccak256(_creationCode(init)));
    }

    function _creationCode(Init calldata init) private view returns (bytes memory) {
        bytes memory initializer = abi.encodeCall(Concord.initialize, (init));
        return abi.encodePacked(type(ConcordProxy).creationCode, abi.encode(implementation, initializer));
    }
}
