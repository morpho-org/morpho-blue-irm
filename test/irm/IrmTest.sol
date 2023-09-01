// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/irm/Irm.sol";

contract IrmTest is Test {
    using MathLib for int256;
    using MathLib for int256;
    using MathLib for uint256;
    using MorphoMathLib for uint128;
    using MorphoMathLib for uint256;
    using MarketParamsLib for MarketParams;

    uint256 internal constant LN2 = 0.69314718056 ether;
    uint256 internal constant TARGET_UTILIZATION = 0.8 ether;
    uint256 internal constant SPEED_FACTOR = uint256(0.01 ether) / uint256(10 hours);
    uint128 internal constant INITIAL_RATE = uint128(0.01 ether) / uint128(365 days);

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
        (uint256 prevBorrowRate, int256 prevErr) = irm.marketIrm(marketParams.id());

        assertEq(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
        assertEq(prevBorrowRate, INITIAL_RATE, "prevBorrowRate");
        assertEq(prevErr, _err(market), "prevErr");
    }

    function testFirstBorrowRateView(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market);
        (uint256 prevBorrowRate, int256 prevErr) = irm.marketIrm(marketParams.id());

        assertEq(avgBorrowRate, INITIAL_RATE, "avgBorrowRate");
        assertEq(prevBorrowRate, 0, "prevBorrowRate");
        assertEq(prevErr, 0, "prevErr");
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
        int256 err = _err(market1);
        int256 prevErr = _err(market0);
        int256 errDelta = err - prevErr;
        uint256 elapsed = block.timestamp - market1.lastUpdate;

        uint256 jumpMultiplier = MathLib.wExp12(errDelta.wMulDown(int256(LN2)));
        int256 speed = int256(SPEED_FACTOR).wMulDown(err);
        uint256 variationMultiplier = MathLib.wExp12(speed * int256(elapsed));
        uint256 expectedBorrowRateAfterJump = INITIAL_RATE.wMulDown(jumpMultiplier);
        uint256 expectedNewBorrowRate = INITIAL_RATE.wMulDown(jumpMultiplier).wMulDown(variationMultiplier);

        uint256 expectedAvgBorrowRate;
        if (speed * int256(elapsed) == 0) {
            expectedAvgBorrowRate = INITIAL_RATE.wMulDown(jumpMultiplier);
        } else {
            expectedAvgBorrowRate = uint256(
                (int256(expectedNewBorrowRate) - int256(expectedBorrowRateAfterJump)).wDivDown(speed * int256(elapsed))
            );
        }

        return (expectedAvgBorrowRate, expectedNewBorrowRate);
    }

    function _err(Market memory market) internal pure returns (int256) {
        uint256 utilization = market.totalBorrowAssets.wDivDown(market.totalSupplyAssets);

        int256 err;
        if (utilization > TARGET_UTILIZATION) {
            // Safe "unchecked" cast because |err| <= WAD.
            err = int256((utilization - TARGET_UTILIZATION).wDivDown(WAD - TARGET_UTILIZATION));
        } else {
            // Safe "unchecked" casts because utilization <= WAD and TARGET_UTILIZATION <= WAD.
            err = (int256(utilization) - int256(TARGET_UTILIZATION)).wDivDown(int256(TARGET_UTILIZATION));
        }
        return err;
    }
}
