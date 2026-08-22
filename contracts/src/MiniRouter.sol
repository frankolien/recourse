// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MiniPair} from "./MiniPair.sol";

// Router and pair registry for MiniPair, exposing the subset of the UniswapV2
// router the wallet actually calls. Keeping those signatures identical is the
// point: engine/src/fx-uniswap-v2.ts quotes through getAmountsOut and does not
// know or care which venue answers, so testnet can run this and mainnet can run
// the real thing without the app changing.
//
// Testnet only. See MiniPair for what is deliberately missing.
contract MiniRouter {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => address)) private _pairs;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair);

    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();
    error PairMissing();
    error Expired();
    error InvalidPath();
    error InsufficientOutputAmount();
    error InsufficientAmount();

    // Taken as a calldata struct rather than eight positional parameters, which
    // overflows the stack at this optimizer setting. The venue layer only ever
    // calls getAmountsOut, so nothing depends on this matching UniswapV2's exact
    // router signature.
    struct AddLiquidity {
        address tokenA;
        address tokenB;
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
        address to;
        uint256 deadline;
    }

    modifier ensure(uint256 deadline) {
        // A swap without a deadline can sit in the mempool and execute later at a
        // price nobody agreed to.
        if (deadline < block.timestamp) revert Expired();
        _;
    }

    function sortTokens(address tokenA, address tokenB) public pure returns (address, address) {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
        return (token0, token1);
    }

    function getPair(address tokenA, address tokenB) public view returns (address) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        return _pairs[token0][token1];
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        if (_pairs[token0][token1] != address(0)) revert PairExists();
        pair = address(new MiniPair(token0, token1));
        _pairs[token0][token1] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair);
    }

    /// The ratio deposited into an empty pair sets the price it trades at.
    function addLiquidity(AddLiquidity calldata p)
        external
        ensure(p.deadline)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        address pair = getPair(p.tokenA, p.tokenB);
        if (pair == address(0)) revert PairMissing();

        (amountA, amountB) = _liquidityAmounts(pair, p);

        IERC20(p.tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(p.tokenB).safeTransferFrom(msg.sender, pair, amountB);
        liquidity = MiniPair(pair).mint(p.to);
    }

    function _liquidityAmounts(address pair, AddLiquidity calldata p)
        private
        view
        returns (uint256 amountA, uint256 amountB)
    {
        (uint256 reserveA, uint256 reserveB) = _reservesFor(pair, p.tokenA, p.tokenB);
        if (reserveA == 0 && reserveB == 0) {
            return (p.amountADesired, p.amountBDesired);
        }
        // Adding at anything other than the current ratio would move the price, so
        // the deposit is trimmed to match it instead.
        uint256 optimalB = (p.amountADesired * reserveB) / reserveA;
        if (optimalB <= p.amountBDesired) {
            if (optimalB < p.amountBMin) revert InsufficientAmount();
            return (p.amountADesired, optimalB);
        }
        uint256 optimalA = (p.amountBDesired * reserveA) / reserveB;
        if (optimalA < p.amountAMin) revert InsufficientAmount();
        return (optimalA, p.amountBDesired);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert InsufficientOutputAmount();

        IERC20(path[0]).safeTransferFrom(msg.sender, getPair(path[0], path[1]), amounts[0]);
        for (uint256 i = 0; i < path.length - 1; i++) {
            // Intermediate hops pay into the next pair rather than back to the caller.
            address recipient = i < path.length - 2 ? getPair(path[i + 1], path[i + 2]) : to;
            _hop(path[i], path[i + 1], amounts[i + 1], recipient);
        }
    }

    // Split out of the loop above so that function's stack stays shallow enough to
    // compile without via-ir.
    function _hop(address tokenIn, address tokenOut, uint256 amountOut, address recipient) private {
        (address token0,) = sortTokens(tokenIn, tokenOut);
        (uint256 amount0Out, uint256 amount1Out) =
            tokenIn == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
        MiniPair(getPair(tokenIn, tokenOut)).swap(amount0Out, amount1Out, recipient);
    }

    /// The UniswapV2 curve: 0.3% fee, integer division, floored.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256)
    {
        if (amountIn == 0) revert InsufficientAmount();
        if (reserveIn == 0 || reserveOut == 0) revert PairMissing();
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        public
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) revert InvalidPath();
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 0; i < path.length - 1; i++) {
            address pair = getPair(path[i], path[i + 1]);
            if (pair == address(0)) revert PairMissing();
            (uint256 reserveIn, uint256 reserveOut) = _reservesFor(pair, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    function _reservesFor(address pair, address tokenA, address tokenB)
        private
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint112 r0, uint112 r1) = MiniPair(pair).getReserves();
        return tokenA == token0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
    }
}
