// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Rule} from "../src/Types.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {RecourseEscrow} from "../src/RecourseEscrow.sol";
import {SettlementVault} from "../src/SettlementVault.sol";
import {TestUSDC} from "../test/mocks/TestUSDC.sol";

// Seeds demo state on a live deployment: one merchant policy, eight payments, two
// disputes with opposite verdicts (one attested NOT_DELIVERED -> full refund, one
// attested DELIVERED -> denied), and one payment advanced by the vault at T+0.
//
// Reads addresses from deployments/<network>.json. Uses three signers from env
// (DEPLOYER_PK is also the attestor here; SEED_MERCHANT_PK, SEED_BUYER_PK) and
// defaults them to well-known anvil keys for the local dry-run. On a non-Arc chain
// USDC is the local mock and buyers are funded by minting; on Arc the deployer funds
// buyer and merchant by USDC transfer (which also credits their native gas balance).
contract Seed is Script {
    uint256 constant ARC = 5042002;

    uint256 deployerPk;
    uint256 merchantPk;
    uint256 buyerPk;
    address deployer;
    address merchant;
    address buyer;

    IERC20 usdc;
    PolicyRegistry registry;
    RecourseEscrow escrow;
    SettlementVault vault;

    uint128 constant PAY = 1e6; // 1 USDC per payment
    uint256 constant N = 8;

    function run() external {
        deployerPk =
            vm.envOr("DEPLOYER_PK", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        merchantPk =
            vm.envOr("SEED_MERCHANT_PK", uint256(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d));
        buyerPk = vm.envOr("SEED_BUYER_PK", uint256(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a));
        deployer = vm.addr(deployerPk);
        merchant = vm.addr(merchantPk);
        buyer = vm.addr(buyerPk);

        _loadDeployment();

        bool local = block.chainid != ARC;
        uint256 buyerFunding = uint256(PAY) * N + 2e6; // payments + gas headroom
        uint256 lpDeposit = 5e6;

        // Phase 1: deployer funds actors, enrolls the merchant, seeds the vault.
        vm.startBroadcast(deployerPk);
        if (local) {
            TestUSDC(address(usdc)).mint(buyer, buyerFunding);
            TestUSDC(address(usdc)).mint(deployer, lpDeposit);
        } else {
            usdc.transfer(buyer, buyerFunding);
            usdc.transfer(merchant, 1e6); // gas for the merchant's policy registration
        }
        vault.enrollMerchant(merchant, 50, 100e6);
        usdc.approve(address(vault), lpDeposit);
        vault.deposit(lpDeposit);
        vm.stopBroadcast();

        // Phase 2: merchant publishes a policy.
        vm.startBroadcast(merchantPk);
        uint256 policyId = registry.registerPolicy(14 days, 0, _rules(), "ipfs://demo-policy");
        vm.stopBroadcast();

        // Phase 3: buyer pays eight times and disputes two of them.
        uint256[] memory ids = new uint256[](N);
        vm.startBroadcast(buyerPk);
        usdc.approve(address(escrow), type(uint256).max);
        for (uint256 i = 0; i < N; i++) {
            ids[i] = escrow.pay(policyId, PAY, bytes32(uint256(i + 1)));
        }
        _fileNotDelivered(ids[4]);
        _fileNotDelivered(ids[5]);
        vm.stopBroadcast();

        // Phase 4: attestor resolves the two disputes to opposite verdicts and the
        // vault advances a still-open payment.
        vm.startBroadcast(deployerPk);
        _attestAndResolve(ids[4], 2); // NOT_DELIVERED -> full refund
        _attestAndResolve(ids[5], 1); // DELIVERED -> denied
        vault.advance(ids[6]);
        vm.stopBroadcast();

        _writeSeedPointers(policyId, ids);
        _report(policyId, ids);
    }

    // rule0: not-delivered, delivery attestation must equal NOT_DELIVERED, full refund.
    // rule1: damaged, photo required, full refund, return required.
    function _rules() internal pure returns (Rule[] memory rules) {
        rules = new Rule[](2);
        rules[0] = Rule({
            claimType: 0,
            requiredEvidenceMask: 0,
            attType: 1,
            attExpected: 2,
            claimWindow: 14 days,
            refundBps: 10000,
            requiresReturn: false
        });
        rules[1] = Rule({
            claimType: 1,
            requiredEvidenceMask: 1,
            attType: 0,
            attExpected: 0,
            claimWindow: 3 days,
            refundBps: 10000,
            requiresReturn: true
        });
    }

    function _fileNotDelivered(uint256 id) internal {
        RecourseEscrow.EvidenceItem[] memory none = new RecourseEscrow.EvidenceItem[](0);
        escrow.fileDispute(id, 0, none);
    }

    function _attestAndResolve(uint256 id, uint8 value) internal {
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 digest = escrow.attestationDigest(id, 1, value, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPk, digest);
        escrow.submitAttestation(id, 1, value, deadline, abi.encodePacked(r, s, v));
        escrow.resolve(id);
    }

    function _loadDeployment() internal {
        string memory file = block.chainid == ARC
            ? "arc-testnet.json"
            : string.concat("local-", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/../deployments/", file));
        usdc = IERC20(vm.parseJsonAddress(json, ".usdc"));
        registry = PolicyRegistry(vm.parseJsonAddress(json, ".policyRegistry"));
        escrow = RecourseEscrow(vm.parseJsonAddress(json, ".escrow"));
        vault = SettlementVault(vm.parseJsonAddress(json, ".settlementVault"));
    }

    function _writeSeedPointers(uint256 policyId, uint256[] memory ids) internal {
        string memory o = "seed";
        vm.serializeUint(o, "policyId", policyId);
        vm.serializeUint(o, "refundPaymentId", ids[4]);
        vm.serializeUint(o, "denyPaymentId", ids[5]);
        string memory json = vm.serializeUint(o, "advancedPaymentId", ids[6]);
        string memory file = block.chainid == ARC
            ? "seed-arc-testnet.json"
            : string.concat("seed-local-", vm.toString(block.chainid), ".json");
        vm.writeJson(json, string.concat(vm.projectRoot(), "/../deployments/", file));
    }

    function _report(uint256 policyId, uint256[] memory ids) internal view {
        console2.log("policyId", policyId);
        console2.log("refund dispute paymentId", ids[4]);
        console2.log("deny dispute paymentId", ids[5]);
        console2.log("vault-advanced paymentId", ids[6]);
        (, bytes32 vh) = escrow.previewVerdict(ids[4]);
        console2.logBytes32(vh);
    }
}
