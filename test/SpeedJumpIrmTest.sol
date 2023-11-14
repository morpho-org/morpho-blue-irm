// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../src/SpeedJumpIrm.sol";

import "../lib/forge-std/src/Test.sol";

contract AdaptativeCurveIrmTest is Test {
    using MathLib for int256;
    using MathLib for int256;
    using MathLib for uint256;
    using UtilsLib for int256;
    using MorphoMathLib for uint128;
    using MorphoMathLib for uint256;
    using MarketParamsLib for MarketParams;

    event BorrowRateUpdate(Id indexed id, uint256 avgBorrowRate, uint256 rateAtTarget);

    int256 internal constant CURVE_STEEPNESS = 4 ether;
    int256 internal constant ADJUSTMENT_SPEED = int256(50 ether) / 365 days;
    int256 internal constant TARGET_UTILIZATION = 0.9 ether;
    int256 internal constant INITIAL_RATE_AT_TARGET = int256(0.01 ether) / 365 days;

    AdaptativeCurveIrm internal irm;
    MarketParams internal marketParams = MarketParams(address(0), address(0), address(0), address(0), 0);

    function setUp() public {
        irm =
        new AdaptativeCurveIrm(address(this), CURVE_STEEPNESS, ADJUSTMENT_SPEED, TARGET_UTILIZATION, INITIAL_RATE_AT_TARGET);
        vm.warp(90 days);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = AdaptativeCurveIrmTest.handleBorrowRate.selector;
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
        targetContract(address(this));
    }

    /* TESTS */

    function testBoundImprovesError(int256 startRateAtTarget, int256 adaptationMultiplier) public {
        // Assume that the start rate at target is in the bounds.
        startRateAtTarget = bound(startRateAtTarget, irm.MIN_RATE_AT_TARGET(), irm.MAX_RATE_AT_TARGET());
        adaptationMultiplier = bound(adaptationMultiplier, 1, MathLib.WEXP_UPPER_VALUE);
        int256 unboundedEndRateAtTarget = startRateAtTarget.wMulDown(adaptationMultiplier);
        int256 endRateAtTarget = unboundedEndRateAtTarget.bound(irm.MIN_RATE_AT_TARGET(), irm.MAX_RATE_AT_TARGET());

        assertLe(_distance(endRateAtTarget, startRateAtTarget), _distance(unboundedEndRateAtTarget, startRateAtTarget));
    }

    function testCurveAtMostMultipliesErrors(int256 err, int256 startRateAtTarget, int256 endRateAtTarget) public {
        // Assume that rates are in the bounds.
        startRateAtTarget = bound(startRateAtTarget, irm.MIN_RATE_AT_TARGET(), irm.MAX_RATE_AT_TARGET());
        endRateAtTarget = bound(endRateAtTarget, irm.MIN_RATE_AT_TARGET(), irm.MAX_RATE_AT_TARGET());
        // Assume that the error is smaller than WAD in absolute value.
        err = bound(err, -1e18, 1e18);

        int256 startBorrowRate = _curve(startRateAtTarget, err);
        int256 endBorrowRate = _curve(endRateAtTarget, err);

        // Sanity check: does not pass if the CURVE_STEEPNESS is decreased by one ether.
        assertLe(
            _distance(startBorrowRate, endBorrowRate),
            _distance(startRateAtTarget, endRateAtTarget).wMulDown(CURVE_STEEPNESS)
        );
    }

    function testLinearAdaptationThresholdEnsuresMaxError1Bps(int256 linearAdaptation, int256 roundingError) public {
        // Assume that the linearAdaptation is not smaller than the threshold.
        linearAdaptation = bound(linearAdaptation, irm.LINEAR_ADAPTATION_THRESHOLD(), type(int64).max);
        // Assume that the initial rounding error is in the theoretical bounds.
        int256 maxRoundingError = 1e18 + irm.MAX_RATE_AT_TARGET() * 3 / 2;
        roundingError = bound(roundingError, 0, maxRoundingError);

        int256 oneBasisPoint = int256(0.0001 ether) / 365 days;

        // Sanity check: does not pass if linearAdaptation is divided by 10.
        assertLe(roundingError.wMulDown(CURVE_STEEPNESS) / linearAdaptation, oneBasisPoint);
    }

    function testDeployment() public {
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        new AdaptativeCurveIrm(address(0), 0, 0, 0, 0);
    }

    function testFirstBorrowRateUtilizationZero() public {
        Market memory market;

        assertApproxEqRel(
            irm.borrowRate(marketParams, market), uint256(INITIAL_RATE_AT_TARGET / 4), 0.0001 ether, "avgBorrowRate"
        );
        assertEq(irm.rateAtTarget(marketParams.id()), INITIAL_RATE_AT_TARGET, "rateAtTarget");
    }

    function testFirstBorrowRateUtilizationOne() public {
        Market memory market;
        market.totalBorrowAssets = 1 ether;
        market.totalSupplyAssets = 1 ether;

        assertEq(irm.borrowRate(marketParams, market), uint256(INITIAL_RATE_AT_TARGET * 4), "avgBorrowRate");
        assertEq(irm.rateAtTarget(marketParams.id()), INITIAL_RATE_AT_TARGET, "rateAtTarget");
    }

    function testFirstBorrowRateUtilizationTarget() public {
        Market memory market;
        market.totalBorrowAssets = 0.9 ether;
        market.totalSupplyAssets = 1 ether;

        assertEq(irm.borrowRate(marketParams, market), uint256(INITIAL_RATE_AT_TARGET), "avgBorrowRate");
        assertEq(irm.rateAtTarget(marketParams.id()), INITIAL_RATE_AT_TARGET, "rateAtTarget");
    }

    function testRateAfterUtilizationOne() public {
        vm.warp(365 days * 2);
        Market memory market;
        assertApproxEqRel(irm.borrowRate(marketParams, market), uint256(INITIAL_RATE_AT_TARGET / 4), 0.001 ether);

        market.totalBorrowAssets = 1 ether;
        market.totalSupplyAssets = 1 ether;
        market.lastUpdate = uint128(block.timestamp - 30 days);

        // (exp((50/365)*30) ~= 61.
        assertApproxEqRel(
            irm.borrowRateView(marketParams, market),
            uint256((INITIAL_RATE_AT_TARGET * 4).wMulDown((61 ether - 1 ether) * WAD / (ADJUSTMENT_SPEED * 30 days))),
            0.1 ether
        );
        // The average value of exp((50/365)*30) between 0 and 30 is approx. 14.58.
        assertApproxEqRel(
            irm.borrowRateView(marketParams, market),
            uint256((INITIAL_RATE_AT_TARGET * 4).wMulDown(14.58 ether)),
            0.1 ether
        );
        // Expected rate: 58%.
        assertApproxEqRel(irm.borrowRateView(marketParams, market), uint256(0.58 ether) / 365 days, 0.1 ether);
    }

    function testRateAfterUtilizationZero() public {
        vm.warp(365 days * 2);
        Market memory market;
        assertApproxEqRel(irm.borrowRate(marketParams, market), uint256(INITIAL_RATE_AT_TARGET / 4), 0.001 ether);

        market.totalBorrowAssets = 0 ether;
        market.totalSupplyAssets = 1 ether;
        market.lastUpdate = uint128(block.timestamp - 30 days);

        // (exp((-50/365)*30) ~= 0.016.
        assertApproxEqRel(
            irm.borrowRateView(marketParams, market),
            uint256(
                (INITIAL_RATE_AT_TARGET / 4).wMulDown((0.016 ether - 1 ether) * WAD / (-ADJUSTMENT_SPEED * 30 days))
            ),
            0.1 ether
        );
        // The average value of exp((-50/365*30)) between 0 and 30 is approx. 0.239.
        assertApproxEqRel(
            irm.borrowRateView(marketParams, market),
            uint256((INITIAL_RATE_AT_TARGET / 4).wMulDown(0.23 ether)),
            0.1 ether
        );
        // Expected rate: 0.057%.
        assertApproxEqRel(irm.borrowRateView(marketParams, market), uint256(0.00057 ether) / 365 days, 0.1 ether);
    }

    function testFirstBorrowRate(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        uint256 avgBorrowRate = irm.borrowRate(marketParams, market);
        int256 rateAtTarget = irm.rateAtTarget(marketParams.id());

        assertEq(avgBorrowRate, _toUint256(_curve(int256(INITIAL_RATE_AT_TARGET), _err(market))), "avgBorrowRate");
        assertEq(rateAtTarget, INITIAL_RATE_AT_TARGET, "rateAtTarget");
    }

    function testBorrowRateEventEmission(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        vm.expectEmit(true, true, true, true, address(irm));
        emit BorrowRateUpdate(
            marketParams.id(),
            _toUint256(_curve(int256(INITIAL_RATE_AT_TARGET), _err(market))),
            uint256(_expectedRateAtTarget(marketParams.id(), market))
        );
        irm.borrowRate(marketParams, market);
    }

    function testFirstBorrowRateView(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market);
        int256 rateAtTarget = irm.rateAtTarget(marketParams.id());

        assertEq(avgBorrowRate, _toUint256(_curve(int256(INITIAL_RATE_AT_TARGET), _err(market))), "avgBorrowRate");
        assertEq(rateAtTarget, 0, "prevBorrowRate");
    }

    function testBorrowRate(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));

        int256 expectedRateAtTarget = _expectedRateAtTarget(marketParams.id(), market1);
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

        int256 expectedRateAtTarget = _expectedRateAtTarget(marketParams.id(), market1);
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

        int256 expectedRateAtTarget = _expectedRateAtTarget(marketParams.id(), market1);
        uint256 expectedAvgRate = _expectedAvgRate(marketParams.id(), market1);

        uint256 borrowRateView = irm.borrowRateView(marketParams, market1);
        uint256 borrowRate = irm.borrowRate(marketParams, market1);

        assertEq(borrowRateView, borrowRate, "borrowRateView");
        assertApproxEqRel(borrowRate, expectedAvgRate, 0.01 ether, "avgBorrowRate");
        assertApproxEqRel(irm.rateAtTarget(marketParams.id()), expectedRateAtTarget, 0.001 ether, "rateAtTarget");
    }

    function testWExpWMulDownMaxRate() public view {
        MathLib.wExp(MathLib.WEXP_UPPER_BOUND).wMulDown(irm.MAX_RATE_AT_TARGET());
    }

    /* HANDLERS */

    function handleBorrowRate(uint256 totalSupplyAssets, uint256 totalBorrowAssets, uint256 elapsed) external {
        elapsed = bound(elapsed, 0, type(uint48).max);
        totalSupplyAssets = bound(totalSupplyAssets, 0, type(uint128).max);
        totalBorrowAssets = bound(totalBorrowAssets, 0, totalSupplyAssets);

        vm.warp(block.timestamp + elapsed);

        Market memory market;
        market.totalBorrowAssets = uint128(totalSupplyAssets);
        market.totalSupplyAssets = uint128(totalBorrowAssets);

        irm.borrowRate(marketParams, market);
    }

    /* INVARIANTS */

    function invariantGeMinRateAtTarget() public {
        Market memory market;
        market.totalBorrowAssets = 9 ether;
        market.totalSupplyAssets = 10 ether;

        assertGe(irm.borrowRateView(marketParams, market), uint256(irm.MIN_RATE_AT_TARGET().wDivDown(CURVE_STEEPNESS)));
        assertGe(irm.borrowRate(marketParams, market), uint256(irm.MIN_RATE_AT_TARGET().wDivDown(CURVE_STEEPNESS)));
    }

    function invariantLeMaxRateAtTarget() public {
        Market memory market;
        market.totalBorrowAssets = 9 ether;
        market.totalSupplyAssets = 10 ether;

        assertLe(irm.borrowRateView(marketParams, market), uint256(irm.MAX_RATE_AT_TARGET().wMulDown(CURVE_STEEPNESS)));
        assertLe(irm.borrowRate(marketParams, market), uint256(irm.MAX_RATE_AT_TARGET().wMulDown(CURVE_STEEPNESS)));
    }

    /* HELPERS */

    function _distance(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? b - a : a - b;
    }

    function _toUint256(int256 x) internal pure returns (uint256) {
        require(x >= 0);
        return uint256(x);
    }

    function _expectedRateAtTarget(Id id, Market memory market) internal view returns (int256) {
        int256 rateAtTarget = int256(irm.rateAtTarget(id));
        int256 speed = ADJUSTMENT_SPEED.wMulDown(_err(market));
        uint256 elapsed = (rateAtTarget > 0) ? block.timestamp - market.lastUpdate : 0;
        int256 linearAdaptation = speed * int256(elapsed);
        int256 adaptationMultiplier = MathLib.wExp(linearAdaptation);
        return (rateAtTarget > 0)
            ? rateAtTarget.wMulDown(adaptationMultiplier).bound(irm.MIN_RATE_AT_TARGET(), irm.MAX_RATE_AT_TARGET())
            : INITIAL_RATE_AT_TARGET;
    }

    function _expectedAvgRate(Id id, Market memory market) internal view returns (uint256) {
        int256 rateAtTarget = int256(irm.rateAtTarget(id));
        int256 err = _err(market);
        int256 speed = ADJUSTMENT_SPEED.wMulDown(err);
        uint256 elapsed = (rateAtTarget > 0) ? block.timestamp - market.lastUpdate : 0;
        int256 linearAdaptation = speed * int256(elapsed);
        int256 endRateAtTarget = int256(_expectedRateAtTarget(id, market));
        uint256 newBorrowRate = _toUint256(_curve(endRateAtTarget, err));

        uint256 avgBorrowRate;
        if (linearAdaptation == 0 || rateAtTarget == 0) {
            avgBorrowRate = newBorrowRate;
        } else {
            // Safe "unchecked" cast to uint256 because linearAdaptation < 0 <=> newBorrowRate <= borrowRateAfterJump.
            avgBorrowRate =
                uint256((int256(newBorrowRate) - int256(_curve(rateAtTarget, err))).wDivDown(linearAdaptation));
        }
        return avgBorrowRate;
    }

    function _curve(int256 rateAtTarget, int256 err) internal pure returns (int256) {
        if (err < 0) {
            return ((WAD - WAD.wDivDown(CURVE_STEEPNESS)).wMulDown(err) + WAD).wMulDown(rateAtTarget);
        } else {
            return ((CURVE_STEEPNESS - WAD).wMulDown(err) + WAD).wMulDown(rateAtTarget);
        }
    }

    function _err(Market memory market) internal pure returns (int256 err) {
        if (market.totalSupplyAssets == 0) return -1 ether;

        int256 utilization = int256(market.totalBorrowAssets.wDivDown(market.totalSupplyAssets));

        if (utilization > TARGET_UTILIZATION) {
            err = (utilization - TARGET_UTILIZATION).wDivDown(WAD - TARGET_UTILIZATION);
        } else {
            err = (utilization - TARGET_UTILIZATION).wDivDown(TARGET_UTILIZATION);
        }
    }
}
