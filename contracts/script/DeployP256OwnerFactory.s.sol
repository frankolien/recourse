// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

import {P256OwnerFactory} from "../src/P256OwnerFactory.sol";

// Deploys the factory that turns a Device Key into a Safe owner, and records it in the
// chain's address book next to the protocol contracts.
//
// Deployed through the deterministic CREATE2 deployer with a fixed salt, so the factory
// lands at the same address on every chain that has that deployer (Arc testnet does),
// and every owner address derived from it stays stable across networks.
//
// Config:
//   RECOURSE_P256_FALLBACK  a Solidity P-256 verifier with the RIP-7212 ABI, retried when
//                           the precompile answers empty. Defaults to Daimo's on Arc
//                           testnet; address(0) means "precompile only".
contract DeployP256OwnerFactory is Script {
    uint256 constant ARC_TESTNET = 5042002;
    address constant DAIMO_VERIFIER_ARC_TESTNET = 0xc2b78104907F722DABAc4C69f826a522B2754De4;
    bytes32 constant SALT = keccak256("recourse.p256-owner-factory.v1");

    function run() external {
        address fallbackVerifier = vm.envOr(
            "RECOURSE_P256_FALLBACK",
            block.chainid == ARC_TESTNET ? DAIMO_VERIFIER_ARC_TESTNET : address(0)
        );

        vm.startBroadcast();
        P256OwnerFactory factory = new P256OwnerFactory{salt: SALT}(fallbackVerifier);
        vm.stopBroadcast();

        string memory file =
            block.chainid == ARC_TESTNET ? "arc-testnet.json" : string.concat("local-", vm.toString(block.chainid), ".json");
        string memory path = string.concat(vm.projectRoot(), "/../deployments/", file);
        vm.writeJson(vm.toString(address(factory)), path, ".p256OwnerFactory");
    }
}
