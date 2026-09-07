// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {DepositVault} from "./DepositVault.sol";
import {IDepositConfig} from "./IDepositBridge.sol";

/// @title DepositFactory
/// @notice Hands out the address a person deposits to, and empties it when money lands.
///
/// There is no owner and no upgrade path. The address someone is shown is a pure
/// function of the Arc account it pays into, so anyone can recompute it and check that
/// the money can only go where they were told.
///
/// The per chain answers live here rather than in the vault so that a vault's creation
/// code is the same everywhere. That is what gives one person one deposit address
/// across every chain this is deployed to, and it means USDC sent on a chain we have
/// not reached yet is waiting rather than lost: deploy this there and it sweeps.
contract DepositFactory is IDepositConfig {
    /// Where the burned dollars are minted. 26 is Arc.
    uint32 public constant ARC_DOMAIN = 26;

    address internal constant MESSENGER_MAINNET = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    address internal constant MESSENGER_TESTNET = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;

    error UnsupportedChain(uint256 chainId);

    event VaultDeployed(bytes32 indexed beneficiary, address vault);

    function destinationDomain() external pure returns (uint32) {
        return ARC_DOMAIN;
    }

    /// USDC and Circle's messenger, by chain. A table rather than constructor arguments
    /// because arguments would change this contract's own address from chain to chain,
    /// and every deposit address hangs off that.
    function _chain() internal view returns (address token, address bridge) {
        uint256 id = block.chainid;
        // Circle deploys its messenger at one address across every EVM mainnet, and a
        // second across every testnet, which is why only the token changes per row.
        // Every pair below was read off that chain on 2026-09-07: the token answers
        // USDC with six decimals, and Circle's minter carries a burn limit for it,
        // which is what proves the bridge will accept it.
        // Base
        if (id == 8453) return (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, MESSENGER_MAINNET);
        if (id == 84532) return (0x036CbD53842c5426634e7929541eC2318f3dCF7e, MESSENGER_TESTNET);
        // Ethereum
        if (id == 1) return (0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, MESSENGER_MAINNET);
        if (id == 11155111) return (0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, MESSENGER_TESTNET);
        // Arbitrum
        if (id == 42161) return (0xaf88d065e77c8cC2239327C5EDb3A432268e5831, MESSENGER_MAINNET);
        if (id == 421614) return (0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d, MESSENGER_TESTNET);
        // Optimism
        if (id == 10) return (0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85, MESSENGER_MAINNET);
        if (id == 11155420) return (0x5fd84259d66Cd46123540766Be93DFE6D43130D7, MESSENGER_TESTNET);
        // Polygon
        if (id == 137) return (0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359, MESSENGER_MAINNET);
        if (id == 80002) return (0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582, MESSENGER_TESTNET);
        // Avalanche
        if (id == 43114) return (0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E, MESSENGER_MAINNET);
        if (id == 43113) return (0x5425890298aed601595a70AB815c96711a31Bc65, MESSENGER_TESTNET);
        // Unichain
        if (id == 130) return (0x078D782b760474a361dDA0AF3839290b0EF57AD6, MESSENGER_MAINNET);
        if (id == 1301) return (0x31d0220469e10c4E71834a79b1f276d740d3768F, MESSENGER_TESTNET);
        // Linea
        if (id == 59144) return (0x176211869cA2b568f2A7D4EE941E073a821EE1ff, MESSENGER_MAINNET);
        if (id == 59141) return (0xFEce4462D57bD51A6A552365A011b95f0E16d9B7, MESSENGER_TESTNET);
        revert UnsupportedChain(id);
    }

    function usdc() external view returns (address token) {
        (token,) = _chain();
    }

    function messenger() external view returns (address bridge) {
        (, bridge) = _chain();
    }

    /// The deposit address for an Arc account, whether or not it has been deployed.
    /// The beneficiary is both the salt and part of the creation code, so it decides
    /// the address twice over.
    function addressFor(bytes32 beneficiary) public view returns (address) {
        return Create2.computeAddress(beneficiary, keccak256(_creationCode(beneficiary)));
    }

    /// Convenience for the common case, an Arc account being a plain address.
    function addressFor(address beneficiary) external view returns (address) {
        return addressFor(bytes32(uint256(uint160(beneficiary))));
    }

    /// Deploy the vault if it is not there yet, then empty it. One transaction.
    /// Idempotent, so two relayers racing each other is not a problem: the loser finds
    /// the vault already deployed, and the sweep reverts with nothing to do.
    function collect(bytes32 beneficiary) public returns (uint256 amount) {
        address vault = addressFor(beneficiary);
        if (vault.code.length == 0) {
            Create2.deploy(0, beneficiary, _creationCode(beneficiary));
            emit VaultDeployed(beneficiary, vault);
        }
        return DepositVault(vault).sweep();
    }

    /// Many at once, so the cost of being a transaction at all is paid once rather than
    /// once per person. A vault with nothing in it, or too little, is skipped instead of
    /// taking the whole batch down with it.
    function collectBatch(bytes32[] calldata beneficiaries) external returns (uint256 swept) {
        for (uint256 i; i < beneficiaries.length; ++i) {
            try this.collect(beneficiaries[i]) {
                ++swept;
            } catch {}
        }
    }

    function _creationCode(bytes32 beneficiary) private pure returns (bytes memory) {
        return abi.encodePacked(type(DepositVault).creationCode, abi.encode(beneficiary));
    }
}
