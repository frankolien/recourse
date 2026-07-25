// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Compiled only to etch onto anvil forks of Arc: the real USDC at 0x3600... depends on
// node-level native-token machinery a fork cannot execute, and dry-running the vault
// (R13) only needs faithful ERC-20 semantics. Never deployed.
contract MockForkUSDC {
    mapping(address => uint256) public balanceOf; // slot 0
    mapping(address => mapping(address => uint256)) public allowance; // slot 1

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }
}
