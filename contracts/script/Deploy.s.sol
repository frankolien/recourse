// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {MockUSYCAdapter} from "../src/MockUSYCAdapter.sol";
import {RecourseEscrow} from "../src/RecourseEscrow.sol";
import {SettlementVault} from "../src/SettlementVault.sol";
import {TestUSDC} from "../test/mocks/TestUSDC.sol";

// Deploys the protocol and writes the address book that everything downstream reads
// (nothing hardcodes an address). On Arc, RECOURSE_USDC must be the real USDC ERC-20;
// with no USDC configured the script deploys a local TestUSDC for dry-runs only, and
// writes to deployments/local-<chainId>.json so it never clobbers arc-testnet.json.
//
// Config (all optional except RECOURSE_USDC on Arc):
//   RECOURSE_USDC, RECOURSE_ATTESTOR, RECOURSE_TREASURY,
//   RECOURSE_YIELD_FEE_BPS (default 1000), RECOURSE_RESOLVE_DELAY (default 60),
//   RECOURSE_ADAPTER_BUFFER (mock path only, default 0)
contract Deploy is Script {
    uint256 constant ARC_TESTNET = 5042002;

    function run() external {
        address deployer = msg.sender;
        address usdcEnv = vm.envOr("RECOURSE_USDC", address(0));
        address attestor = vm.envOr("RECOURSE_ATTESTOR", deployer);
        address treasury = vm.envOr("RECOURSE_TREASURY", deployer);
        uint16 yieldFeeBps = uint16(vm.envOr("RECOURSE_YIELD_FEE_BPS", uint256(1000)));
        uint64 resolveDelay = uint64(vm.envOr("RECOURSE_RESOLVE_DELAY", uint256(60)));
        uint256 buffer = vm.envOr("RECOURSE_ADAPTER_BUFFER", uint256(0));

        require(block.chainid != ARC_TESTNET || usdcEnv != address(0), "set RECOURSE_USDC on Arc");

        vm.startBroadcast();

        IERC20 usdc = usdcEnv == address(0) ? IERC20(address(new TestUSDC())) : IERC20(usdcEnv);
        PolicyRegistry registry = new PolicyRegistry();
        MockUSYCAdapter adapter = new MockUSYCAdapter(usdc);
        RecourseEscrow escrow =
            new RecourseEscrow(usdc, registry, adapter, attestor, treasury, yieldFeeBps, resolveDelay);
        SettlementVault vault = new SettlementVault(usdc, escrow);
        escrow.setVault(address(vault));

        // Only the local mock can be minted; the real USDC buffer is funded from the faucet separately.
        if (usdcEnv == address(0) && buffer > 0) {
            TestUSDC(address(usdc)).mint(address(adapter), buffer);
        }

        vm.stopBroadcast();

        _writeAddresses(usdc, registry, adapter, escrow, vault, attestor, treasury);
    }

    function _writeAddresses(
        IERC20 usdc,
        PolicyRegistry registry,
        MockUSYCAdapter adapter,
        RecourseEscrow escrow,
        SettlementVault vault,
        address attestor,
        address treasury
    ) internal {
        string memory o = "deployment";
        vm.serializeUint(o, "chainId", block.chainid);
        vm.serializeAddress(o, "usdc", address(usdc));
        vm.serializeAddress(o, "policyRegistry", address(registry));
        vm.serializeAddress(o, "yieldAdapter", address(adapter));
        vm.serializeAddress(o, "escrow", address(escrow));
        vm.serializeAddress(o, "settlementVault", address(vault));
        vm.serializeAddress(o, "attestor", attestor);
        string memory json = vm.serializeAddress(o, "treasury", treasury);

        string memory file =
            block.chainid == ARC_TESTNET ? "arc-testnet.json" : string.concat("local-", vm.toString(block.chainid), ".json");
        vm.writeJson(json, string.concat(vm.projectRoot(), "/../deployments/", file));
    }
}
