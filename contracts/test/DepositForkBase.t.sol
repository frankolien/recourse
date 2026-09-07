// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";

import {DepositFactory} from "../src/deposit/DepositFactory.sol";
import {DepositVault} from "../src/deposit/DepositVault.sol";
import {IERC20Minimal} from "../src/deposit/IDepositBridge.sol";

/// The deposit path against the real Circle contracts on Base, not stand-ins.
///
/// Mocks can only agree with whatever the author assumed. This runs the same sweep
/// against the CCTP v2 TokenMessenger and the real USDC that a deposit would meet, and
/// reads the burn back out of the log Circle's attestation service actually indexes.
/// Skipped unless BASE_SEPOLIA_RPC_URL is set, so the normal suite stays offline.
contract DepositForkBaseTest is Test {
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant MESSENGER = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;
    address constant MESSAGE_TRANSMITTER = 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275;

    /// `MessageSent(bytes)`, the one event Circle's attestation service watches for.
    bytes32 constant MESSAGE_SENT = keccak256("MessageSent(bytes)");

    DepositFactory factory;
    address ada = address(0xADA);
    bool live;

    function setUp() public {
        string memory url = vm.envOr("BASE_SEPOLIA_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        live = true;
        factory = new DepositFactory();
    }

    /// Give the deposit address dollars the way an exchange withdrawal would: by moving
    /// the balance, with no call into the vault at all.
    function _fund(address vault, uint256 amount) internal {
        deal(USDC, vault, amount);
    }

    function test_ForkSweepBurnsThroughRealCctp() public {
        if (!live) return;

        address vault = factory.addressFor(ada);
        _fund(vault, 25_000_000);
        assertEq(IERC20Minimal(USDC).balanceOf(vault), 25_000_000, "funded like a withdrawal");

        vm.recordLogs();
        uint256 swept = factory.collect(bytes32(uint256(uint160(ada))));

        assertEq(swept, 25_000_000);
        assertEq(IERC20Minimal(USDC).balanceOf(vault), 0, "the dollars left");

        // The message Circle will attest. Its body carries the destination and the
        // recipient, which is what proves the money is addressed to Ada on Arc.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes memory message;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == MESSAGE_TRANSMITTER && logs[i].topics[0] == MESSAGE_SENT) {
                message = abi.decode(logs[i].data, (bytes));
            }
        }
        assertGt(message.length, 0, "CCTP emitted a message");

        // Header layout, CCTP v2: version, source domain, destination domain at byte 8.
        assertEq(uint32(bytes4(_slice(message, 8, 4))), 26, "addressed to Arc");
        assertEq(uint32(bytes4(_slice(message, 4, 4))), 6, "sent from Base");
    }

    /// The address a person is given must be the one the real chain agrees with.
    function test_ForkAddressMatchesTheChain() public {
        if (!live) return;
        address vault = factory.addressFor(ada);
        _fund(vault, 5_000_000);
        factory.collect(bytes32(uint256(uint160(ada))));
        assertGt(vault.code.length, 0, "deployed exactly where it was promised");
        assertEq(DepositVault(vault).BENEFICIARY(), bytes32(uint256(uint160(ada))));
    }

    function _slice(bytes memory data, uint256 start, uint256 length) private pure returns (bytes memory out) {
        out = new bytes(length);
        for (uint256 i; i < length; ++i) {
            out[i] = data[start + i];
        }
    }
}
