// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../src/SpeedJumpIrm.sol";

import "../lib/forge-std/src/Test.sol";

contract AdaptativeCurveIrmTest is Test {
    using MathLib for int256;
    using MathLib for int256;
    using MathLib for uint256;
    using UtilsLib for uint256;
    using MorphoMathLib for uint128;
    using MorphoMathLib for uint256;
    using MarketParamsLib for MarketParams;

    event BorrowRateUpdate(Id indexed id, uint256 avgBorrowRate, uint256 rateAtTarget);

    uint256 internal constant CURVE_STEEPNESS = 4 ether;
    uint256 internal constant ADJUSTMENT_SPEED = 50 ether / uint256(365 days);
    uint256 internal constant TARGET_UTILIZATION = 0.9 ether;
    uint256 internal constant INITIAL_RATE_AT_TARGET = 0.01 ether / uint256(365 days);

    AdaptativeCurveIrm internal irm;
    MarketParams internal marketParams = MarketParams(address(0), address(0), address(0), address(0), 0);

    function setUp() public {
        irm =
        new AdaptativeCurveIrm(address(this), CURVE_STEEPNESS, ADJUSTMENT_SPEED, TARGET_UTILIZATION, INITIAL_RATE_AT_TARGET);
        vm.warp(90 days);
    }

    function testDeployment() public {
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        new AdaptativeCurveIrm(address(0), 0, 0, 0, 0);
    }

    function testFirstBorrowRateUtilizationZero() public {
        Market memory market;

        assertEq(irm.borrowRate(marketParams, market), INITIAL_RATE_AT_TARGET / 4, "avgBorrowRate");
        assertEq(irm.rateAtTarget(marketParams.id()), INITIAL_RATE_AT_TARGET, "rateAtTarget");
    }

    function testFirstBorrowRateUtilizationOne() public {
        Market memory market;
        market.totalBorrowAssets = 1 ether;
        market.totalSupplyAssets = 1 ether;

        assertEq(irm.borrowRate(marketParams, market), INITIAL_RATE_AT_TARGET * 4, "avgBorrowRate");
        assertEq(irm.rateAtTarget(marketParams.id()), INITIAL_RATE_AT_TARGET, "rateAtTarget");
    }

    function testFirstBorrowRateUtilizationTarget() public {
        Market memory market;
        market.totalBorrowAssets = 0.9 ether;
        market.totalSupplyAssets = 1 ether;

        assertEq(irm.borrowRate(marketParams, market), INITIAL_RATE_AT_TARGET, "avgBorrowRate");
        assertEq(irm.rateAtTarget(marketParams.id()), INITIAL_RATE_AT_TARGET, "rateAtTarget");
    }

    function testRateAfterUtilizationOne() public {
        Market memory market;
        irm.borrowRate(marketParams, market);

        vm.warp(365 days * 2);

        market.totalBorrowAssets = 1 ether;
        market.totalSupplyAssets = 1 ether;
        market.lastUpdate = uint128(block.timestamp - 365 days);
        irm.borrowRate(marketParams, market);

        // TODO: fix
        // assertGt(irm.borrowRate(marketParams, market), INITIAL_RATE_AT_TARGET * 50 * 4);
    }

    function testFirstBorrowRate(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        uint256 avgBorrowRate = irm.borrowRate(marketParams, market);
        uint256 rateAtTarget = irm.rateAtTarget(marketParams.id());

        assertEq(avgBorrowRate, _curve(INITIAL_RATE_AT_TARGET, _err(market)), "avgBorrowRate");
        assertEq(rateAtTarget, INITIAL_RATE_AT_TARGET, "rateAtTarget");
    }

    function testBorrowRateEventEmission(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        vm.expectEmit(true, true, true, true, address(irm));
        emit BorrowRateUpdate(
            marketParams.id(),
            _curve(INITIAL_RATE_AT_TARGET, _err(market)),
            _expectedRateAtTarget(marketParams.id(), market)
        );
        irm.borrowRate(marketParams, market);
    }

    function testFirstBorrowRateView(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market);
        uint256 rateAtTarget = irm.rateAtTarget(marketParams.id());

        assertEq(avgBorrowRate, _curve(INITIAL_RATE_AT_TARGET, _err(market)), "avgBorrowRate");
        assertEq(rateAtTarget, 0, "prevBorrowRate");
    }

    function testBorrowRate(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));

        uint256 expectedRateAtTarget = _expectedRateAtTarget(marketParams.id(), market1);
        uint256 expectedAvgRate = _expectedAvgRate(marketParams.id(), market1);

        uint256 borrowRateView = irm.borrowRateView(marketParams, market1);
        uint256 borrowRate = irm.borrowRate(marketParams, market1);

        assertEq(borrowRateView, borrowRate, "borrowRateView");
        assertApproxEqRel(borrowRate, expectedAvgRate, 0.01 ether, "avgBorrowRate");
        assertApproxEqRel(irm.rateAtTarget(marketParams.id()), expectedRateAtTarget, 0.001 ether, "rateAtTarget");
    }

    function testBorrowRateNoTimeElapsed(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(block.timestamp);

        uint256 expectedRateAtTarget = _expectedRateAtTarget(marketParams.id(), market1);
        uint256 expectedAvgRate = _expectedAvgRate(marketParams.id(), market1);

        uint256 borrowRateView = irm.borrowRateView(marketParams, market1);
        uint256 borrowRate = irm.borrowRate(marketParams, market1);

        assertEq(borrowRateView, borrowRate, "borrowRateView");
        assertApproxEqRel(borrowRate, expectedAvgRate, 0.01 ether, "avgBorrowRate");
        assertApproxEqRel(irm.rateAtTarget(marketParams.id()), expectedRateAtTarget, 0.001 ether, "rateAtTarget");
    }

    function testBorrowRateNoUtilizationChange(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        market1.totalBorrowAssets = market0.totalBorrowAssets;
        market1.totalSupplyAssets = market0.totalSupplyAssets;
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));

        uint256 expectedRateAtTarget = _expectedRateAtTarget(marketParams.id(), market1);
        uint256 expectedAvgRate = _expectedAvgRate(marketParams.id(), market1);

        uint256 borrowRateView = irm.borrowRateView(marketParams, market1);
        uint256 borrowRate = irm.borrowRate(marketParams, market1);

        assertEq(borrowRateView, borrowRate, "borrowRateView");
        assertApproxEqRel(borrowRate, expectedAvgRate, 0.01 ether, "avgBorrowRate");
        assertApproxEqRel(irm.rateAtTarget(marketParams.id()), expectedRateAtTarget, 0.001 ether, "rateAtTarget");
    }

    function invariantMinRateAtTarget() public {
        Market memory market;
        market.totalBorrowAssets = 9 ether;
        market.totalSupplyAssets = 10 ether;
        assertGt(irm.borrowRate(marketParams, market), irm.MIN_RATE_AT_TARGET().wDivDown(CURVE_STEEPNESS));
    }

    function invariantMaxRateAtTarget() public {
        Market memory market;
        market.totalBorrowAssets = 9 ether;
        market.totalSupplyAssets = 10 ether;
        assertLt(irm.borrowRate(marketParams, market), irm.MAX_RATE_AT_TARGET().wMulDown(CURVE_STEEPNESS));
    }

    function _expectedRateAtTarget(Id id, Market memory market) internal view returns (uint256) {
        uint256 rateAtTarget = irm.rateAtTarget(id);
        int256 speed = int256(ADJUSTMENT_SPEED).wMulDown(_err(market));
        uint256 elapsed = (rateAtTarget > 0) ? block.timestamp - market.lastUpdate : 0;
        int256 linearVariation = speed * int256(elapsed);
        uint256 variationMultiplier = MathLib.wExp(linearVariation);
        return (rateAtTarget > 0)
            ? rateAtTarget.wMulDown(variationMultiplier).bound(irm.MIN_RATE_AT_TARGET(), irm.MAX_RATE_AT_TARGET())
            : INITIAL_RATE_AT_TARGET;
    }

    function _expectedAvgRate(Id id, Market memory market) internal view returns (uint256) {
        uint256 rateAtTarget = irm.rateAtTarget(id);
        int256 err = _err(market);
        int256 speed = int256(ADJUSTMENT_SPEED).wMulDown(err);
        uint256 elapsed = (rateAtTarget > 0) ? block.timestamp - market.lastUpdate : 0;
        int256 linearVariation = speed * int256(elapsed);
        uint256 newRateAtTarget = _expectedRateAtTarget(id, market);
        uint256 newBorrowRate = _curve(newRateAtTarget, err);

        uint256 avgBorrowRate;
        if (linearVariation == 0 || rateAtTarget == 0) {
            avgBorrowRate = newBorrowRate;
        } else {
            // Safe "unchecked" cast to uint256 because linearVariation < 0 <=> newBorrowRate <= borrowRateAfterJump.
            avgBorrowRate =
                uint256((int256(newBorrowRate) - int256(_curve(rateAtTarget, err))).wDivDown(linearVariation));
        }
        return avgBorrowRate;
    }

    function _curve(uint256 rateAtTarget, int256 err) internal pure returns (uint256) {
        // Safe "unchecked" cast because err >= -1 (in WAD).
        if (err < 0) {
            return uint256((WAD_INT - WAD_INT.wDivDown(int256(CURVE_STEEPNESS))).wMulDown(err) + WAD_INT).wMulDown(
                rateAtTarget
            );
        }
        return uint256((int256(CURVE_STEEPNESS) - WAD_INT).wMulDown(err) + WAD_INT).wMulDown(rateAtTarget);
    }

    function _err(Market memory market) internal pure returns (int256) {
        if (market.totalSupplyAssets == 0) return -1 ether;
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
