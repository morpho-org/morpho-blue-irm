// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/irm/Irm.sol";

contract IrmTest is Test {
    using MathLib for int256;
    using MathLib for uint128;
    using MathLib for uint256;
    using IrmMathLib for int256;
    using IrmMathLib for uint256;
    using MarketParamsLib for MarketParams;

    uint256 internal constant LN2 = 0.69314718056 ether;
    uint256 internal constant TARGET_UTILIZATION = 0.8 ether;
    uint256 internal constant SPEED_FACTOR = uint256(0.01 ether) / uint256(10 hours);
    uint256 internal constant INITIAL_RATE = uint256(0.01 ether) / uint256(365 days);

    Irm internal irm;
    MarketParams internal marketParams = MarketParams(address(0), address(0), address(0), address(0), 0);

    function setUp() public {
        irm = new Irm(address(this), LN2, SPEED_FACTOR, TARGET_UTILIZATION, INITIAL_RATE);
        vm.warp(90 days);
    }

    function testFirstBorrowRate(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);
        uint256 avgBorrowRate = irm.borrowRate(marketParams, market);
        assertEq(avgBorrowRate, INITIAL_RATE);
        uint256 expectedUtilization = market.totalBorrowAssets.wDivDown(market.totalSupplyAssets);
        (uint256 prevBorrowRate, uint256 prevUtilization) = irm.marketIrm(marketParams.id());
        assertEq(prevBorrowRate, INITIAL_RATE);
        assertEq(prevUtilization, expectedUtilization);
    }

    function testFirstBorrowRateView(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);
        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market);
        assertEq(avgBorrowRate, INITIAL_RATE);
        (uint256 prevBorrowRate, uint256 prevUtilization) = irm.marketIrm(marketParams.id());
        assertEq(prevBorrowRate, 0);
        assertEq(prevUtilization, 0);
    }

    function testBorrowRate(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));
        uint256 avgBorrowRate = irm.borrowRate(marketParams, market1);

        uint256 utilization0 = market0.totalBorrowAssets.wDivDown(market0.totalSupplyAssets);
        uint256 utilization1 = market1.totalBorrowAssets.wDivDown(market1.totalSupplyAssets);
        (uint256 prevBorrowRate, uint256 prevUtilization) = irm.marketIrm(marketParams.id());
        assertEq(prevUtilization, utilization1);

        if (utilization0 <= utilization1 && utilization1 >= TARGET_UTILIZATION) {
            assertGe(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
            assertGe(prevBorrowRate, INITIAL_RATE, "prevBorrowRate");
        } else if (utilization0 >= utilization1 && utilization1 <= TARGET_UTILIZATION) {
            assertLt(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
            assertLt(prevBorrowRate, INITIAL_RATE, "prevBorrowRate");
        }
    }

    function testBorrowRateView(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));
        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market1);

        uint256 utilization0 = market0.totalBorrowAssets.wDivDown(market0.totalSupplyAssets);
        uint256 utilization1 = market1.totalBorrowAssets.wDivDown(market1.totalSupplyAssets);
        (uint256 prevBorrowRate, uint256 prevUtilization) = irm.marketIrm(marketParams.id());
        assertEq(prevUtilization, utilization0);
        assertEq(prevBorrowRate, INITIAL_RATE);

        if (utilization0 <= utilization1 && utilization1 >= TARGET_UTILIZATION) {
            assertGe(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
        } else if (utilization0 >= utilization1 && utilization1 <= TARGET_UTILIZATION) {
            assertLt(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
        }
    }

    function testBorrowRateJumpOnly(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(block.timestamp);
        uint256 avgBorrowRate = irm.borrowRate(marketParams, market1);

        uint256 utilization0 = market0.totalBorrowAssets.wDivDown(market0.totalSupplyAssets);
        uint256 utilization1 = market1.totalBorrowAssets.wDivDown(market1.totalSupplyAssets);
        (uint256 prevBorrowRate,) = irm.marketIrm(marketParams.id());
        assertEq(prevBorrowRate, avgBorrowRate, "prev/avgBorrowRate");

        int256 errDelta = int256(utilization1) - int256(utilization0);
        uint256 jumpMultiplier = IrmMathLib.wExp(int256(LN2), errDelta);
        uint256 expectedBorrowRate = INITIAL_RATE.wMulDown(jumpMultiplier);
        assertEq(avgBorrowRate, expectedBorrowRate, "avgBorrowRate");

        if (utilization0 <= utilization1) assertGe(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
        else assertLe(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
    }

    function testBorrowRateJumpOnlyView(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(block.timestamp);
        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market1);

        uint256 utilization0 = market0.totalBorrowAssets.wDivDown(market0.totalSupplyAssets);
        uint256 utilization1 = market1.totalBorrowAssets.wDivDown(market1.totalSupplyAssets);
        int256 errDelta = int256(utilization1) - int256(utilization0);
        uint256 jumpMultiplier = IrmMathLib.wExp(int256(LN2), errDelta);
        uint256 expectedBorrowRate = INITIAL_RATE.wMulDown(jumpMultiplier);
        assertEq(avgBorrowRate, expectedBorrowRate, "avgBorrowRate");

        if (utilization0 <= utilization1) assertGe(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
        else assertLe(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
    }

    function testBorrowRateSpeedOnly(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        market1.totalBorrowAssets = market0.totalBorrowAssets;
        market1.totalSupplyAssets = market0.totalSupplyAssets;
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));
        uint256 avgBorrowRate = irm.borrowRate(marketParams, market1);

        uint256 utilization = market1.totalBorrowAssets.wDivDown(market1.totalSupplyAssets);
        int256 err = int256(utilization) - int256(TARGET_UTILIZATION);
        int256 speed = int256(SPEED_FACTOR).wMulDown(err);
        uint256 elapsed = block.timestamp - market1.lastUpdate;
        uint256 variationMultiplier = IrmMathLib.wExp(speed * int256(elapsed));
        uint256 expectedBorrowRate = INITIAL_RATE.wMulDown(variationMultiplier);
        (uint256 prevBorrowRate,) = irm.marketIrm(marketParams.id());
        assertEq(prevBorrowRate, expectedBorrowRate, "prevBorrowRate");

        uint256 expectedAvgBorrowRate = uint256(
            int256(INITIAL_RATE).wMulDown(int256(variationMultiplier) - WAD_INT).wDivDown(speed * int256(elapsed))
        );
        assertEq(avgBorrowRate, expectedAvgBorrowRate, "avgBorrowRate");

        if (utilization <= TARGET_UTILIZATION) assertLe(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
        else assertGt(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
    }

    function testBorrowRateSpeedOnlyView(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        market1.totalBorrowAssets = market0.totalBorrowAssets;
        market1.totalSupplyAssets = market0.totalSupplyAssets;
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));
        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market1);

        uint256 utilization = market0.totalBorrowAssets.wDivDown(market0.totalSupplyAssets);
        int256 err = int256(utilization) - int256(TARGET_UTILIZATION);
        int256 speed = int256(SPEED_FACTOR).wMulDown(err);
        uint256 elapsed = block.timestamp - market1.lastUpdate;
        uint256 variationMultiplier = IrmMathLib.wExp(speed * int256(elapsed));
        uint256 expectedAvgBorrowRate = uint256(
            int256(INITIAL_RATE).wMulDown(int256(variationMultiplier) - WAD_INT).wDivDown(speed * int256(elapsed))
        );
        assertEq(avgBorrowRate, expectedAvgBorrowRate, "avgBorrowRate");

        if (utilization <= TARGET_UTILIZATION) assertLe(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
        else assertGt(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
    }
}
