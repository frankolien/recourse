// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC3009} from "../src/interfaces/IERC3009.sol";

// Checks the assumptions payWithAuthorization rests on against the real Arc USDC
// rather than against the mock, because the mock is a reimplementation of what
// Circle's FiatTokenV2 is believed to do and that belief is what needs checking
// before any of this moves money (R13).
//
// What a fork cannot do here: Arc USDC delegates balances and transfers to a chain
// level precompile at 0x1800...0000, in 18 decimals, which no local EVM implements.
// Forking and calling transfer fails with StackUnderflow inside that precompile, so
// the value movement half of this path is only testable against a live Arc node or
// against the mock. What a fork can still settle is the part that would otherwise
// fail silently in production: which EIP-3009 entry points exist, and the exact
// EIP-712 domain a payer must sign under.
//
// Skipped unless ARC_RPC_URL is set, so the default suite stays offline:
//   ARC_RPC_URL=https://arc-testnet.drpc.org forge test --match-contract ArcForkAgent
contract ArcForkAgentTest is Test {
    address constant ARC_USDC = 0x3600000000000000000000000000000000000000;
    // Circle's GatewayWallet, the largest USDC holder on Arc testnet.
    address constant USDC_WHALE = 0x0077777d7EBA4688BDeF3E311b846F25870A19B9;
    uint256 constant ARC_TESTNET = 5042002;

    IERC20 usdc;
    address buyer;
    bool forked;

    function setUp() public {
        string memory rpc = vm.envOr("ARC_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;

        vm.createSelectFork(rpc);
        forked = true;
        buyer = makeAddr("buyer");
        usdc = IERC20(ARC_USDC);
    }

    // The EIP-3009 surface the design depends on, asserted against deployed bytecode
    // rather than against documentation.
    function test_arcUsdcSpeaksEip3009() public view {
        if (!forked) return;

        assertEq(IERC3009(ARC_USDC).authorizationState(address(1), bytes32(0)), false);

        (bool ok, bytes memory data) = ARC_USDC.staticcall(abi.encodeWithSignature("version()"));
        assertTrue(ok, "version() missing");
        assertEq(abi.decode(data, (string)), "2", "EIP-712 domain version");

        (ok, data) = ARC_USDC.staticcall(abi.encodeWithSignature("name()"));
        assertTrue(ok, "name() missing");
        assertEq(abi.decode(data, (string)), "USDC");
    }

    // The failure this exists to prevent: signing under the wrong EIP-712 domain
    // produces a signature the token rejects, and no amount of local mock testing
    // would reveal it. Reconstructing the domain from name and version and matching
    // it against the deployed token settles that without moving value.
    function test_eip712DomainMatchesWhatAPayerWouldSign() public view {
        if (!forked) return;
        assertEq(block.chainid, ARC_TESTNET, "fork is not Arc testnet");

        (, bytes memory sepData) = ARC_USDC.staticcall(abi.encodeWithSignature("DOMAIN_SEPARATOR()"));

        bytes32 reconstructed = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("USDC")),
                keccak256(bytes("2")),
                block.chainid,
                ARC_USDC
            )
        );

        assertEq(reconstructed, abi.decode(sepData, (bytes32)), "a payer signing under this domain would be rejected");
    }

    // Asserted rather than left as a comment, so the day Arc implements this in
    // bytecode the constraint above fails loudly instead of quietly going stale.
    function test_transfersAreBackedByAPrecompileAndCannotBeForked() public {
        if (!forked) return;

        vm.prank(USDC_WHALE);
        (bool ok,) = ARC_USDC.call(abi.encodeWithSignature("transfer(address,uint256)", buyer, uint256(1e6)));
        assertFalse(ok, "transfer now works on a fork; the precompile assumption is stale");
        assertEq(usdc.balanceOf(buyer), 0);
    }
}
