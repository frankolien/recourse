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
    uint256 constant ARC_MAINNET = 5042;
    address constant DAIMO_VERIFIER_ARC_TESTNET = 0xc2b78104907F722DABAc4C69f826a522B2754De4;
    bytes32 constant SALT = keccak256("recourse.p256-owner-factory.v1");

    function run() external {
        // Arc mainnet answers the RIP-7212 precompile itself, checked on 2026-09-23 by
        // handing 0x100 a genuinely valid signature and reading back 1, so no Solidity
        // fallback is wired there. A fallback of zero is a decision, not an omission.
        address fallbackVerifier = vm.envOr(
            "RECOURSE_P256_FALLBACK",
            block.chainid == ARC_TESTNET ? DAIMO_VERIFIER_ARC_TESTNET : address(0)
        );

        vm.startBroadcast();
        P256OwnerFactory factory = new P256OwnerFactory{salt: SALT}(fallbackVerifier);
        vm.stopBroadcast();

        // Named by chain id, which is the convention every chain after Arc testnet
        // follows. Anything unrecognised is a local node and keeps the local- prefix,
        // so a stray anvil run cannot overwrite a real chain's address book.
        string memory file;
        if (block.chainid == ARC_TESTNET) {
            file = "arc-testnet.json";
        } else if (block.chainid == ARC_MAINNET) {
            file = "5042.json";
        } else {
            file = string.concat("local-", vm.toString(block.chainid), ".json");
        }
        string memory path = string.concat(vm.projectRoot(), "/../deployments/", file);
        vm.writeJson(vm.toString(address(factory)), path, ".p256OwnerFactory");
    }
}
