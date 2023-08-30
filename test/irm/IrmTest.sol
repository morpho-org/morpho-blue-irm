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
        (uint256 prevBorrowRate, uint256 prevUtilization) = irm.marketIrm(marketParams.id());

        uint256 expectedUtilization = market.totalBorrowAssets.wDivDown(market.totalSupplyAssets);

        assertEq(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
        assertEq(prevBorrowRate, INITIAL_RATE, "prevBorrowRate");
        assertEq(prevUtilization, expectedUtilization, "prevUtilization");
    }

    function testFirstBorrowRateView(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market);
        (uint256 prevBorrowRate, uint256 prevUtilization) = irm.marketIrm(marketParams.id());

        assertEq(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
        assertEq(prevBorrowRate, 0, "prevBorrowRate");
        assertEq(prevUtilization, 0, "prevUtilization");
    }

    function testBorrowRate(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));

        uint256 avgBorrowRate = irm.borrowRate(marketParams, market1);
        (uint256 prevBorrowRate,) = irm.marketIrm(marketParams.id());

        (uint256 expectedAvgBorrowRate, uint256 expectedPrevBorrowRate) = _expectedBorrowRates(market0, market1);

        assertEq(prevBorrowRate, expectedPrevBorrowRate, "prevBorrowRate");
        assertEq(avgBorrowRate, expectedAvgBorrowRate, "avgBorrowRate");
    }

    function testBorrowRateView(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));

        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market1);
        (uint256 prevBorrowRate,) = irm.marketIrm(marketParams.id());

        (uint256 expectedAvgBorrowRate,) = _expectedBorrowRates(market0, market1);

        assertEq(prevBorrowRate, INITIAL_RATE, "prevBorrowRate");
        assertEq(avgBorrowRate, expectedAvgBorrowRate, "avgBorrowRate");
    }

    function testBorrowRateJumpOnly(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(block.timestamp);

        uint256 avgBorrowRate = irm.borrowRate(marketParams, market1);
        (uint256 prevBorrowRate,) = irm.marketIrm(marketParams.id());

        (uint256 expectedAvgBorrowRate, uint256 expectedPrevBorrowRate) = _expectedBorrowRates(market0, market1);

        assertEq(expectedAvgBorrowRate, expectedPrevBorrowRate, "expectedAvgBorrowRate");
        assertEq(avgBorrowRate, expectedAvgBorrowRate, "avgBorrowRate");
        assertEq(prevBorrowRate, expectedPrevBorrowRate, "prevBorrowRate");
    }

    function testBorrowRateViewJumpOnly(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(block.timestamp);

        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market1);
        (uint256 prevBorrowRate,) = irm.marketIrm(marketParams.id());

        (uint256 expectedAvgBorrowRate,) = _expectedBorrowRates(market0, market1);

        assertEq(prevBorrowRate, INITIAL_RATE, "prevBorrowRate");
        assertEq(avgBorrowRate, expectedAvgBorrowRate, "avgBorrowRate");
    }

    function testBorrowRateSpeedOnly(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        market1.totalBorrowAssets = market0.totalBorrowAssets;
        market1.totalSupplyAssets = market0.totalSupplyAssets;
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));

        uint256 avgBorrowRate = irm.borrowRate(marketParams, market1);
        (uint256 prevBorrowRate,) = irm.marketIrm(marketParams.id());

        (uint256 expectedAvgBorrowRate, uint256 expectedPrevBorrowRate) = _expectedBorrowRates(market0, market1);

        assertEq(prevBorrowRate, expectedPrevBorrowRate, "prevBorrowRate");
        assertEq(avgBorrowRate, expectedAvgBorrowRate, "avgBorrowRate");
    }

    function testBorrowRateViewSpeedOnly(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        market1.totalBorrowAssets = market0.totalBorrowAssets;
        market1.totalSupplyAssets = market0.totalSupplyAssets;
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));

        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market1);
        (uint256 prevBorrowRate,) = irm.marketIrm(marketParams.id());

        (uint256 expectedAvgBorrowRate,) = _expectedBorrowRates(market0, market1);

        assertEq(prevBorrowRate, INITIAL_RATE, "prevBorrowRate");
        assertEq(avgBorrowRate, expectedAvgBorrowRate, "avgBorrowRate");
    }

    /// @dev Returns the expected `avgBorrowRate` and `prevBorrowRate`.
    function _expectedBorrowRates(Market memory market0, Market memory market1)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 utilization0 = market0.totalBorrowAssets.wDivDown(market0.totalSupplyAssets);
        uint256 utilization1 = market1.totalBorrowAssets.wDivDown(market1.totalSupplyAssets);
        int256 err = int256(utilization1) - int256(TARGET_UTILIZATION);
        int256 errDelta = int256(utilization1) - int256(utilization0);
        uint256 elapsed = block.timestamp - market1.lastUpdate;

        uint256 jumpMultiplier = IrmMathLib.wExp3(errDelta.wMulDown(int256(LN2)));
        int256 speed = int256(SPEED_FACTOR).wMulDown(err);
        uint256 variationMultiplier = IrmMathLib.wExp12(speed * int256(elapsed));
        uint256 expectedPrevBorrowRate = INITIAL_RATE.wMulDown(jumpMultiplier).wMulDown(variationMultiplier);

        uint256 expectedAvgBorrowRate;
        if (speed * int256(elapsed) == 0) {
            expectedAvgBorrowRate = INITIAL_RATE.wMulDown(jumpMultiplier);
        } else {
            expectedAvgBorrowRate = uint256(
                int256(INITIAL_RATE.wMulDown(jumpMultiplier)).wMulDown(int256(variationMultiplier) - WAD_INT).wDivDown(
                    speed * int256(elapsed)
                )
            );
        }

        return (expectedAvgBorrowRate, expectedPrevBorrowRate);
    }
}
