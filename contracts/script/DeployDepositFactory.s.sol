// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {DepositFactory} from "../src/deposit/DepositFactory.sol";

/// Puts the deposit factory on a chain people already keep dollars on.
///
/// Deployed through the deterministic CREATE2 deployer with a fixed salt, so it lands at
/// the same address on Base, Arbitrum and Ethereum. That is what makes one person's
/// deposit address the same on all of them, and it is why USDC sent to the right address
/// on a chain we have not reached yet is waiting rather than lost: run this there and it
/// sweeps.
///
///   forge script script/DeployDepositFactory.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL \
///     --broadcast --private-key $DEPLOYER_PK
contract DeployDepositFactory is Script {
    bytes32 constant FACTORY_SALT = keccak256("recourse.deposit.v1.factory");
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        require(CREATE2_DEPLOYER.code.length != 0, "no deterministic deployer on this chain");

        address predicted = _predict(FACTORY_SALT, type(DepositFactory).creationCode);

        vm.startBroadcast();
        // Already there means already correct: the address is a pure function of the code.
        if (predicted.code.length == 0) {
            address deployed = address(new DepositFactory{salt: FACTORY_SALT}());
            require(deployed == predicted, "landed somewhere unexpected");
        }
        vm.stopBroadcast();

        DepositFactory factory = DepositFactory(predicted);
        console.log("chain", block.chainid);
        console.log("deposit factory", predicted);
        console.log("usdc", factory.usdc());
        console.log("messenger", factory.messenger());
        // A worked example, so the operator can eyeball that the maths agrees with the
        // backend before anybody is told to send money anywhere.
        console.log("example address for 0x...dEaD", factory.addressFor(address(0xdEaD)));
    }

    function _predict(bytes32 salt, bytes memory creationCode) private pure returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, salt, keccak256(creationCode)))))
        );
    }
}
