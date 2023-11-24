// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../src/AdaptiveCurveIrm.sol";

import "../../lib/forge-std/src/Test.sol";

contract AdaptiveCurveIrmTest is Test {
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

    AdaptiveCurveIrm internal irm;
    MarketParams internal marketParams = MarketParams(address(0), address(0), address(0), address(0), 0);

    function setUp() public {
        irm =
        new AdaptiveCurveIrm(address(this), CURVE_STEEPNESS, ADJUSTMENT_SPEED, TARGET_UTILIZATION, INITIAL_RATE_AT_TARGET);
        vm.warp(90 days);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = AdaptiveCurveIrmTest.handleBorrowRate.selector;
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
        targetContract(address(this));
    }

    /* TESTS */

    function testDeployment() public {
        vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
        new AdaptiveCurveIrm(address(0), 0, 0, 0, 0);
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

    function testRateAfterUtilizationOne() public {
        vm.warp(365 days * 2);
        Market memory market;
        assertApproxEqRel(irm.borrowRate(marketParams, market), uint256(INITIAL_RATE_AT_TARGET / 4), 0.001 ether);

        market.totalBorrowAssets = 1 ether;
        market.totalSupplyAssets = 1 ether;
        market.lastUpdate = uint128(block.timestamp - 5 days);

        // (exp((50/365)*5) ~= 1.9836.
        assertApproxEqRel(
            irm.borrowRateView(marketParams, market),
            uint256((INITIAL_RATE_AT_TARGET * 4).wMulDown((1.9836 ether - 1 ether) * WAD / (ADJUSTMENT_SPEED * 5 days))),
            0.1 ether
        );
        // The average value of exp((50/365)*x) between 0 and 5 is approx. 1.4361.
        assertApproxEqRel(
            irm.borrowRateView(marketParams, market),
            uint256((INITIAL_RATE_AT_TARGET * 4).wMulDown(1.4361 ether)),
            0.1 ether
        );
        // Expected rate: 5.744%.
        assertApproxEqRel(irm.borrowRateView(marketParams, market), uint256(0.05744 ether) / 365 days, 0.1 ether);
    }

    function testRateAfterUtilizationZero() public {
        vm.warp(365 days * 2);
        Market memory market;
        assertApproxEqRel(irm.borrowRate(marketParams, market), uint256(INITIAL_RATE_AT_TARGET / 4), 0.001 ether);

        market.totalBorrowAssets = 0 ether;
        market.totalSupplyAssets = 1 ether;
        market.lastUpdate = uint128(block.timestamp - 5 days);

        // (exp((-50/365)*5) ~= 0.5041.
        assertApproxEqRel(
            irm.borrowRateView(marketParams, market),
            uint256(
                (INITIAL_RATE_AT_TARGET / 4).wMulDown((0.5041 ether - 1 ether) * WAD / (-ADJUSTMENT_SPEED * 5 days))
            ),
            0.1 ether
        );
        // The average value of exp((-50/365*x)) between 0 and 5 is approx. 0.7240.
        assertApproxEqRel(
            irm.borrowRateView(marketParams, market),
            uint256((INITIAL_RATE_AT_TARGET / 4).wMulDown(0.724 ether)),
            0.1 ether
        );
        // Expected rate: 0.181%.
        assertApproxEqRel(irm.borrowRateView(marketParams, market), uint256(0.00181 ether) / 365 days, 0.1 ether);
    }

    function testRateAfter45DaysUtilizationAboveTargetNoPing() public {
        Market memory market;
        market.totalSupplyAssets = 1 ether;
        market.totalBorrowAssets = uint128(uint256(TARGET_UTILIZATION));
        assertEq(irm.borrowRate(marketParams, market), uint256(INITIAL_RATE_AT_TARGET));
        assertEq(irm.rateAtTarget(marketParams.id()), INITIAL_RATE_AT_TARGET);

        market.lastUpdate = uint128(block.timestamp);
        vm.warp(block.timestamp + 45 days);

        market.totalBorrowAssets = uint128(uint256(TARGET_UTILIZATION + 1 ether) / 2); // Error = 50%
        irm.borrowRate(marketParams, market);

        // Expected rate: 1% * exp(50 * 45 / 365 * 50%) = 21.81%.
        assertApproxEqRel(irm.rateAtTarget(marketParams.id()), int256(0.2181 ether) / 365 days, 0.005 ether);
    }

    function testRateAfter45DaysUtilizationAboveTargetPingEveryMinute() public {
        Market memory market;
        market.totalSupplyAssets = 1 ether;
        market.totalBorrowAssets = uint128(uint256(TARGET_UTILIZATION));
        assertEq(irm.borrowRate(marketParams, market), uint256(INITIAL_RATE_AT_TARGET));
        assertEq(irm.rateAtTarget(marketParams.id()), INITIAL_RATE_AT_TARGET);

        uint128 initialBorrowAssets = uint128(uint256(TARGET_UTILIZATION + 1 ether) / 2); // Error = 50%

        market.totalBorrowAssets = initialBorrowAssets;

        for (uint256 i; i < 45 days / 1 minutes; ++i) {
            market.lastUpdate = uint128(block.timestamp);
            vm.warp(block.timestamp + 1 minutes);

            uint256 avgBorrowRate = irm.borrowRate(marketParams, market);
            uint256 interest = market.totalBorrowAssets.wMulDown(avgBorrowRate.wTaylorCompounded(1 minutes));
            market.totalSupplyAssets += uint128(interest);
            market.totalBorrowAssets += uint128(interest);
        }

        assertApproxEqRel(
            market.totalBorrowAssets.wDivDown(market.totalSupplyAssets), 0.95 ether, 0.002 ether, "utilization"
        );

        int256 rateAtTarget = irm.rateAtTarget(marketParams.id());
        // Expected rate: 1% * exp(50 * 45 / 365 * 50%) = 21.81%.
        int256 expectedRateAtTarget = int256(0.2181 ether) / 365 days;
        assertGe(rateAtTarget, expectedRateAtTarget);
        // The rate is tolerated to be +2% (relatively) because of the pings every minute.
        assertApproxEqRel(rateAtTarget, expectedRateAtTarget, 0.02 ether, "expectedRateAtTarget");

        // Expected growth: exp(21.81% * 3.5 * 45 / 365) = +9.87%.
        // The growth is tolerated to be +8% (relatively) because of the pings every minute.
        assertApproxEqRel(
            market.totalBorrowAssets, initialBorrowAssets.wMulDown(1.0987 ether), 0.08 ether, "totalBorrowAssets"
        );
    }

    function testRateAfterUtilizationTargetNoPing(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, type(uint48).max);

        Market memory market;
        market.totalSupplyAssets = 1 ether;
        market.totalBorrowAssets = uint128(uint256(TARGET_UTILIZATION));
        assertEq(irm.borrowRate(marketParams, market), uint256(INITIAL_RATE_AT_TARGET));
        assertEq(irm.rateAtTarget(marketParams.id()), INITIAL_RATE_AT_TARGET);

        market.lastUpdate = uint128(block.timestamp);
        vm.warp(block.timestamp + elapsed);

        irm.borrowRate(marketParams, market);

        assertEq(irm.rateAtTarget(marketParams.id()), INITIAL_RATE_AT_TARGET);
    }

    function testRateAfter3WeeksUtilizationTargetPingEveryMinute() public {
        int256 initialRateAtTarget = int256(1 ether) / 365 days; // 100%

        irm =
        new AdaptiveCurveIrm(address(this), CURVE_STEEPNESS, ADJUSTMENT_SPEED, TARGET_UTILIZATION, initialRateAtTarget);

        Market memory market;
        market.totalSupplyAssets = 1 ether;
        market.totalBorrowAssets = uint128(uint256(TARGET_UTILIZATION));
        assertEq(irm.borrowRate(marketParams, market), uint256(initialRateAtTarget));
        assertEq(irm.rateAtTarget(marketParams.id()), initialRateAtTarget);

        for (uint256 i; i < 3 weeks / 1 minutes; ++i) {
            market.lastUpdate = uint128(block.timestamp);
            vm.warp(block.timestamp + 1 minutes);

            uint256 avgBorrowRate = irm.borrowRate(marketParams, market);
            uint256 interest = market.totalBorrowAssets.wMulDown(avgBorrowRate.wTaylorCompounded(1 minutes));
            market.totalSupplyAssets += uint128(interest);
            market.totalBorrowAssets += uint128(interest);
        }

        assertApproxEqRel(
            market.totalBorrowAssets.wDivDown(market.totalSupplyAssets), uint256(TARGET_UTILIZATION), 0.01 ether
        );

        int256 rateAtTarget = irm.rateAtTarget(marketParams.id());
        assertGe(rateAtTarget, initialRateAtTarget);
        // The rate is tolerated to be +10% (relatively) because of the pings every minute.
        assertApproxEqRel(rateAtTarget, initialRateAtTarget, 0.1 ether);
    }

    function testFirstBorrowRate(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        uint256 avgBorrowRate = irm.borrowRate(marketParams, market);
        int256 rateAtTarget = irm.rateAtTarget(marketParams.id());

        assertEq(avgBorrowRate, _curve(int256(INITIAL_RATE_AT_TARGET), _err(market)), "avgBorrowRate");
        assertEq(rateAtTarget, INITIAL_RATE_AT_TARGET, "rateAtTarget");
    }

    function testBorrowRateEventEmission(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        vm.expectEmit(true, true, true, true, address(irm));
        emit BorrowRateUpdate(
            marketParams.id(),
            _curve(int256(INITIAL_RATE_AT_TARGET), _err(market)),
            uint256(_expectedRateAtTarget(marketParams.id(), market))
        );
        irm.borrowRate(marketParams, market);
    }

    function testFirstBorrowRateView(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market);
        int256 rateAtTarget = irm.rateAtTarget(marketParams.id());

        assertEq(avgBorrowRate, _curve(int256(INITIAL_RATE_AT_TARGET), _err(market)), "avgBorrowRate");
        assertEq(rateAtTarget, 0, "prevBorrowRate");
    }

    function testBorrowRate(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(bound(market1.lastUpdate, block.timestamp - 5 days, block.timestamp - 1));

        int256 expectedRateAtTarget = _expectedRateAtTarget(marketParams.id(), market1);
        uint256 expectedAvgRate = _expectedAvgRate(marketParams.id(), market1);

        uint256 borrowRateView = irm.borrowRateView(marketParams, market1);
        uint256 borrowRate = irm.borrowRate(marketParams, market1);

        assertEq(borrowRateView, borrowRate, "borrowRateView");
        assertApproxEqRel(borrowRate, expectedAvgRate, 0.11 ether, "avgBorrowRate");
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
        market1.lastUpdate = uint128(bound(market1.lastUpdate, block.timestamp - 5 days, block.timestamp - 1));

        int256 expectedRateAtTarget = _expectedRateAtTarget(marketParams.id(), market1);
        uint256 expectedAvgRate = _expectedAvgRate(marketParams.id(), market1);

        uint256 borrowRateView = irm.borrowRateView(marketParams, market1);
        uint256 borrowRate = irm.borrowRate(marketParams, market1);

        assertEq(borrowRateView, borrowRate, "borrowRateView");
        assertApproxEqRel(borrowRate, expectedAvgRate, 0.1 ether, "avgBorrowRate");
        assertApproxEqRel(irm.rateAtTarget(marketParams.id()), expectedRateAtTarget, 0.001 ether, "rateAtTarget");
    }

    /* HANDLERS */

    function handleBorrowRate(uint256 totalSupplyAssets, uint256 totalBorrowAssets, uint256 elapsed) external {
        elapsed = bound(elapsed, 0, type(uint48).max);
        totalSupplyAssets = bound(totalSupplyAssets, 0, type(uint128).max);
        totalBorrowAssets = bound(totalBorrowAssets, 0, totalSupplyAssets);

        Market memory market;
        market.lastUpdate = uint128(block.timestamp);
        market.totalBorrowAssets = uint128(totalSupplyAssets);
        market.totalSupplyAssets = uint128(totalBorrowAssets);

        vm.warp(block.timestamp + elapsed);
        irm.borrowRate(marketParams, market);
    }

    /* INVARIANTS */

    function invariantGeMinRateAtTarget() public {
        Market memory market;
        market.totalBorrowAssets = 9 ether;
        market.totalSupplyAssets = 10 ether;

        assertGe(
            irm.borrowRateView(marketParams, market), uint256(ConstantsLib.MIN_RATE_AT_TARGET.wDivDown(CURVE_STEEPNESS))
        );
        assertGe(
            irm.borrowRate(marketParams, market), uint256(ConstantsLib.MIN_RATE_AT_TARGET.wDivDown(CURVE_STEEPNESS))
        );
    }

    function invariantLeMaxRateAtTarget() public {
        Market memory market;
        market.totalBorrowAssets = 9 ether;
        market.totalSupplyAssets = 10 ether;

        assertLe(
            irm.borrowRateView(marketParams, market), uint256(ConstantsLib.MAX_RATE_AT_TARGET.wMulDown(CURVE_STEEPNESS))
        );
        assertLe(
            irm.borrowRate(marketParams, market), uint256(ConstantsLib.MAX_RATE_AT_TARGET.wMulDown(CURVE_STEEPNESS))
        );
    }

    /* HELPERS */

    function _expectedRateAtTarget(Id id, Market memory market) internal view returns (int256) {
        int256 rateAtTarget = int256(irm.rateAtTarget(id));
        int256 speed = ADJUSTMENT_SPEED.wMulDown(_err(market));
        uint256 elapsed = (rateAtTarget > 0) ? block.timestamp - market.lastUpdate : 0;
        int256 linearAdaptation = speed * int256(elapsed);
        int256 adaptationMultiplier = ExpLib.wExp(linearAdaptation);
        return (rateAtTarget > 0)
            ? rateAtTarget.wMulDown(adaptationMultiplier).bound(
                ConstantsLib.MIN_RATE_AT_TARGET, ConstantsLib.MAX_RATE_AT_TARGET
            )
            : INITIAL_RATE_AT_TARGET;
    }

    function _expectedAvgRate(Id id, Market memory market) internal view returns (uint256) {
        int256 rateAtTarget = int256(irm.rateAtTarget(id));
        int256 err = _err(market);
        int256 speed = ADJUSTMENT_SPEED.wMulDown(err);
        uint256 elapsed = (rateAtTarget > 0) ? block.timestamp - market.lastUpdate : 0;
        int256 linearAdaptation = speed * int256(elapsed);
        int256 endRateAtTarget = int256(_expectedRateAtTarget(id, market));
        uint256 newBorrowRate = _curve(endRateAtTarget, err);

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

    function _curve(int256 rateAtTarget, int256 err) internal pure returns (uint256) {
        // Safe "unchecked" cast because err >= -1 (in WAD).
        if (err < 0) {
            return uint256(((WAD - WAD.wDivDown(CURVE_STEEPNESS)).wMulDown(err) + WAD).wMulDown(rateAtTarget));
        } else {
            return uint256(((CURVE_STEEPNESS - WAD).wMulDown(err) + WAD).wMulDown(rateAtTarget));
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
