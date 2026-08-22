// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// A constant product pair, deliberately minimal, for seeding testnet FX liquidity.
//
// It exists because Arc has nowhere honest to convert: the one DEX there holds
// under $600 and its USDC/EURC pool quotes 2.2x off the real rate, so a wallet
// routing through it would take most of a user's money. Uniswap V2 itself is
// Solidity 0.5 and 0.6 and does not build in this repo, so this reimplements the
// same curve and the same 0.3% fee at 0.8.
//
// Not for mainnet. No flash swaps, no price oracle, no protocol fee, no factory
// permissioning. Mainnet points the FXVenue interface at a real venue instead.
contract MiniPair {
    using SafeERC20 for IERC20;

    address public immutable token0;
    address public immutable token1;

    uint112 private reserve0;
    uint112 private reserve1;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    // Burned on the first mint so totalSupply can never return to zero, which would
    // let someone re-seed the pool at an arbitrary price.
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    uint256 private unlocked = 1;

    event Mint(address indexed to, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(address indexed to, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out);

    error Locked();
    error InsufficientLiquidityMinted();
    error InsufficientOutput();
    error InsufficientLiquidity();
    error InvalidTo();
    error InsufficientInput();
    error KInvariant();
    error Overflow();

    modifier lock() {
        if (unlocked != 1) revert Locked();
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112, uint112) {
        return (reserve0, reserve1);
    }

    /// Tokens must already have been transferred in. Caller is the router.
    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 r0, uint112 r1) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - r0;
        uint256 amount1 = balance1 - r1;

        uint256 supply = totalSupply;
        if (supply == 0) {
            liquidity = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            totalSupply = MINIMUM_LIQUIDITY;
            balanceOf[address(0)] = MINIMUM_LIQUIDITY;
        } else {
            uint256 byToken0 = (amount0 * supply) / r0;
            uint256 byToken1 = (amount1 * supply) / r1;
            liquidity = byToken0 < byToken1 ? byToken0 : byToken1;
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();

        totalSupply += liquidity;
        balanceOf[to] += liquidity;
        _update(balance0, balance1);
        emit Mint(to, amount0, amount1, liquidity);
    }

    /// Input must already have been transferred in, matching UniswapV2's shape.
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external lock {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutput();
        (uint112 r0, uint112 r1) = getReserves();
        if (amount0Out >= r0 || amount1Out >= r1) revert InsufficientLiquidity();
        if (to == token0 || to == token1) revert InvalidTo();

        if (amount0Out > 0) IERC20(token0).safeTransfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).safeTransfer(to, amount1Out);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > r0 - amount0Out ? balance0 - (r0 - amount0Out) : 0;
        uint256 amount1In = balance1 > r1 - amount1Out ? balance1 - (r1 - amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) revert InsufficientInput();

        // The 0.3% fee is charged by requiring k to hold against balances net of it,
        // which is what makes the fee accrue to liquidity providers rather than
        // being skimmed somewhere.
        uint256 adjusted0 = balance0 * 1000 - amount0In * 3;
        uint256 adjusted1 = balance1 * 1000 - amount1In * 3;
        if (adjusted0 * adjusted1 < uint256(r0) * uint256(r1) * 1_000_000) revert KInvariant();

        _update(balance0, balance1);
        emit Swap(to, amount0In, amount1In, amount0Out, amount1Out);
    }

    function _update(uint256 balance0, uint256 balance1) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Overflow();
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
    }

    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
