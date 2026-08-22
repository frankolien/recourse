// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MiniPair} from "../src/MiniPair.sol";
import {MiniRouter} from "../src/MiniRouter.sol";
import {TestUSDC} from "./mocks/TestUSDC.sol";

// The testnet FX venue. What matters here is that this reproduces the UniswapV2
// curve exactly, because engine/src/fx-uniswap-v2.ts mirrors the same formula and
// quotes users against it. A divergence would quote one number and fill another.
contract MiniAmmTest is Test {
    TestUSDC usdc;
    TestUSDC eurc;
    MiniRouter router;
    address pair;

    address lp = address(0xA1);
    address trader = address(0xB2);

    // The reference rate on 2026-08-13: EUR/USD 1.1534.
    uint256 constant SEED_USDC = 23_070_000;
    uint256 constant SEED_EURC = 20_000_000;

    function setUp() public {
        usdc = new TestUSDC();
        eurc = new TestUSDC();
        router = new MiniRouter();
        pair = router.createPair(address(usdc), address(eurc));

        usdc.mint(lp, 1_000_000_000);
        eurc.mint(lp, 1_000_000_000);
        usdc.mint(trader, 1_000_000_000);

        vm.startPrank(lp);
        usdc.approve(address(router), type(uint256).max);
        eurc.approve(address(router), type(uint256).max);
        router.addLiquidity(
            MiniRouter.AddLiquidity({
                tokenA: address(usdc), tokenB: address(eurc),
                amountADesired: SEED_USDC, amountBDesired: SEED_EURC,
                amountAMin: 0, amountBMin: 0, to: lp, deadline: block.timestamp
            })
        );
        vm.stopPrank();
    }

    function test_seedingSetsTheReserves() public view {
        (uint112 r0, uint112 r1) = MiniPair(pair).getReserves();
        (uint256 rUsdc, uint256 rEurc) =
            address(usdc) < address(eurc) ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        assertEq(rUsdc, SEED_USDC);
        assertEq(rEurc, SEED_EURC);
    }

    // Pinned against the same inputs asserted in engine/test/fx.test.ts. A drift
    // between the two is invisible in either suite alone.
    function test_curveMatchesTheTypeScriptMirror() public view {
        assertEq(router.getAmountOut(1_000_000, 1_000_000_000, 2_000_000_000), 1_992_013);
    }

    function test_quoteEqualsTheFill() public {
        uint256 amountIn = 400_000; // inside the guard the wallet enforces
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(eurc);

        uint256[] memory quoted = router.getAmountsOut(amountIn, path);
        uint256 before = eurc.balanceOf(trader);

        vm.startPrank(trader);
        usdc.approve(address(router), amountIn);
        router.swapExactTokensForTokens(amountIn, quoted[1], path, trader, block.timestamp);
        vm.stopPrank();

        // The number a user is shown must be the number they receive.
        assertEq(eurc.balanceOf(trader) - before, quoted[1]);
    }

    function test_swapRespectsMinimumOut() public {
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(eurc);
        uint256[] memory quoted = router.getAmountsOut(400_000, path);

        vm.startPrank(trader);
        usdc.approve(address(router), 400_000);
        vm.expectRevert(MiniRouter.InsufficientOutputAmount.selector);
        router.swapExactTokensForTokens(400_000, quoted[1] + 1, path, trader, block.timestamp);
        vm.stopPrank();
    }

    function test_expiredSwapReverts() public {
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(eurc);

        vm.warp(1000);
        vm.startPrank(trader);
        usdc.approve(address(router), 400_000);
        vm.expectRevert(MiniRouter.Expired.selector);
        router.swapExactTokensForTokens(400_000, 0, path, trader, 999);
        vm.stopPrank();
    }

    // The invariant the whole thing rests on: a swap may never reduce k.
    function testFuzz_swapNeverReducesK(uint96 amountIn) public {
        amountIn = uint96(bound(amountIn, 1_000, 10_000_000));
        (uint112 a0, uint112 a1) = MiniPair(pair).getReserves();
        uint256 kBefore = uint256(a0) * uint256(a1);

        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(eurc);

        vm.startPrank(trader);
        usdc.approve(address(router), amountIn);
        router.swapExactTokensForTokens(amountIn, 0, path, trader, block.timestamp);
        vm.stopPrank();

        (uint112 b0, uint112 b1) = MiniPair(pair).getReserves();
        assertGe(uint256(b0) * uint256(b1), kBefore);
    }

    // Price impact rises with size, which is what makes the wallet's deviation
    // guard meaningful rather than decorative.
    function test_largerTradesPriceWorse() public view {
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(eurc);

        uint256 small = router.getAmountsOut(100_000, path)[1];
        uint256 large = router.getAmountsOut(5_000_000, path)[1];
        assertGt(small * 50, large); // 50x the input returns less than 50x the output
    }

    function test_secondPairCannotBeCreatedTwice() public {
        vm.expectRevert(MiniRouter.PairExists.selector);
        router.createPair(address(eurc), address(usdc));
    }
}
