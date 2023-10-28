// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../src/SpeedJumpIrm.sol";

import "../lib/forge-std/src/Test.sol";

contract SpeedJumpIrmTest is Test {
    using MathLib for int256;
    using MathLib for int256;
    using MathLib for uint256;
    using UtilsLib for uint256;
    using MorphoMathLib for uint128;
    using MorphoMathLib for uint256;
    using MarketParamsLib for MarketParams;

    event BorrowRateUpdate(Id indexed id, uint256 avgBorrowRate, uint256 baseBorrowRate);

    uint256 internal constant LN2 = 0.69314718056 ether;
    uint256 internal constant TARGET_UTILIZATION = 0.8 ether;
    uint256 internal constant SPEED_FACTOR = uint256(0.01 ether) / uint256(10 hours);
    // rate for utilization=0 and baseRate=initialBaseRate.
    uint256 internal constant INITIAL_RATE = uint128(0.01 ether) / uint128(365 days);
    uint256 internal constant INITIAL_BASE_RATE = uint256(INITIAL_RATE) * LN2 / 1 ether;

    SpeedJumpIrm internal irm;
    MarketParams internal marketParams = MarketParams(address(0), address(0), address(0), address(0), 0);

    function setUp() public {
        irm = new SpeedJumpIrm(address(this), LN2, SPEED_FACTOR, TARGET_UTILIZATION, INITIAL_BASE_RATE);
        vm.warp(90 days);
    }

    function testFirstBorrowRateEmptyMarket() public {
        Market memory market;
        uint256 avgBorrowRate = irm.borrowRate(marketParams, market);
        uint256 baseRate = irm.baseRate(marketParams.id());

        assertEq(
            avgBorrowRate,
            INITIAL_BASE_RATE.wMulDown(MathLib.wExp(int256(-1 ether).wMulDown(int256(LN2)))),
            "avgBorrowRate"
        );
        assertEq(baseRate, INITIAL_BASE_RATE, "baseRate");
    }

    function testFirstBorrowRate(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        uint256 avgBorrowRate = irm.borrowRate(marketParams, market);
        uint256 baseRate = irm.baseRate(marketParams.id());

        assertEq(
            avgBorrowRate, INITIAL_BASE_RATE.wMulDown(MathLib.wExp(_err(market).wMulDown(int256(LN2)))), "avgBorrowRate"
        );
        assertEq(baseRate, INITIAL_BASE_RATE, "baseRate");
    }

    function _testBorrowRateEventEmission(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        vm.expectEmit(address(irm));
        emit BorrowRateUpdate(marketParams.id(), INITIAL_RATE, INITIAL_RATE);
        irm.borrowRate(marketParams, market);
    }

    function testFirstBorrowRateView(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market);
        uint256 baseRate = irm.baseRate(marketParams.id());

        assertEq(
            avgBorrowRate, INITIAL_BASE_RATE.wMulDown(MathLib.wExp(_err(market).wMulDown(int256(LN2)))), "avgBorrowRate"
        );
        assertEq(baseRate, 0, "prevBorrowRate");
    }

    function testBorrowRate(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));

        uint256 expectedBaseRate = _expectedBaseRate(marketParams.id(), market1);
        uint256 expectedAvgRate = _expectedAvgRateCurve(marketParams.id(), market1);
        uint256 expectedAvgRate2 = _expectedAvgRate(market0, market1);

        uint256 borrowRate = irm.borrowRate(marketParams, market1);

        assertApproxEqRel(borrowRate, expectedAvgRate, 0.01 ether, "avgBorrowRate");
        assertApproxEqRel(borrowRate, expectedAvgRate2, 0.01 ether, "avgBorrowRate2");
        assertApproxEqRel(irm.baseRate(marketParams.id()), expectedBaseRate, 0.001 ether, "baseRate");
    }

    function testBorrowRateView(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));

        assertApproxEqRel(
            irm.borrowRateView(marketParams, market1), _expectedAvgRate(market0, market1), 0.01 ether, "avgBorrowRate"
        );
    }

    function testBorrowRateJumpOnly(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(block.timestamp);

        uint256 expectedBaseRate = _expectedBaseRate(marketParams.id(), market1);
        uint256 expectedAvgRate = _expectedAvgRateCurve(marketParams.id(), market1);
        uint256 expectedAvgRate2 = _expectedAvgRate(market0, market1);

        uint256 borrowRate = irm.borrowRate(marketParams, market1);

        assertApproxEqRel(borrowRate, expectedAvgRate, 0.01 ether, "avgBorrowRate");
        assertApproxEqRel(borrowRate, expectedAvgRate2, 0.01 ether, "avgBorrowRate2");
        assertApproxEqRel(irm.baseRate(marketParams.id()), expectedBaseRate, 0.001 ether, "baseRate");
    }

    function testBorrowRateViewJumpOnly(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        market1.lastUpdate = uint128(block.timestamp);

        assertApproxEqRel(
            irm.borrowRateView(marketParams, market1),
            _expectedAvgRateCurve(marketParams.id(), market1),
            0.01 ether,
            "avgBorrowRate"
        );
        assertApproxEqRel(
            irm.borrowRateView(marketParams, market1), _expectedAvgRate(market0, market1), 0.01 ether, "avgBorrowRate"
        );
    }

    function testBorrowRateSpeedOnly(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        market1.totalBorrowAssets = market0.totalBorrowAssets;
        market1.totalSupplyAssets = market0.totalSupplyAssets;
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));

        uint256 expectedBaseRate = _expectedBaseRate(marketParams.id(), market1);
        uint256 expectedAvgRate = _expectedAvgRateCurve(marketParams.id(), market1);
        uint256 expectedAvgRate2 = _expectedAvgRate(market0, market1);

        uint256 borrowRate = irm.borrowRate(marketParams, market1);

        assertApproxEqRel(borrowRate, expectedAvgRate, 0.01 ether, "avgBorrowRate");
        assertApproxEqRel(borrowRate, expectedAvgRate2, 0.01 ether, "avgBorrowRate2");
        assertApproxEqRel(irm.baseRate(marketParams.id()), expectedBaseRate, 0.001 ether, "baseRate");
    }

    function testBorrowRateViewSpeedOnly(Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        irm.borrowRate(marketParams, market0);

        market1.totalBorrowAssets = market0.totalBorrowAssets;
        market1.totalSupplyAssets = market0.totalSupplyAssets;
        market1.lastUpdate = uint128(bound(market1.lastUpdate, 0, block.timestamp - 1));

        assertApproxEqRel(
            irm.borrowRateView(marketParams, market1),
            _expectedAvgRateCurve(marketParams.id(), market1),
            0.01 ether,
            "avgBorrowRate"
        );
        assertApproxEqRel(
            irm.borrowRateView(marketParams, market1), _expectedAvgRate(market0, market1), 0.01 ether, "avgBorrowRate"
        );
    }

    function _expectedBaseRate(Id id, Market memory market) internal view returns (uint256) {
        uint256 baseRate = irm.baseRate(id);
        int256 speed = int256(SPEED_FACTOR).wMulDown(_err(market));
        uint256 elapsed = (baseRate > 0) ? block.timestamp - market.lastUpdate : 0;
        int256 linearVariation = speed * int256(elapsed);
        uint256 variationMultiplier = MathLib.wExp(linearVariation);
        return (baseRate > 0) ? baseRate.wMulDown(variationMultiplier) : INITIAL_BASE_RATE;
    }

    function _expectedAvgRateCurve(Id id, Market memory market) internal view returns (uint256) {
        uint256 baseRate = irm.baseRate(id);
        int256 speed = int256(SPEED_FACTOR).wMulDown(_err(market));
        uint256 elapsed = (baseRate > 0) ? block.timestamp - market.lastUpdate : 0;
        int256 linearVariation = speed * int256(elapsed);
        uint256 variationMultiplier = MathLib.wExp(linearVariation);
        uint256 newBaseRate = (baseRate > 0) ? baseRate.wMulDown(variationMultiplier) : INITIAL_BASE_RATE;
        uint256 newBorrowRate = newBaseRate.wMulDown(MathLib.wExp(_err(market).wMulDown(int256(LN2))));

        uint256 avgBorrowRate;
        if (linearVariation == 0 || baseRate == 0) {
            avgBorrowRate = newBorrowRate;
        } else {
            // Safe "unchecked" cast to uint256 because linearVariation < 0 <=> newBorrowRate <= borrowRateAfterJump.
            avgBorrowRate = uint256(
                (int256(newBorrowRate) - int256(baseRate.wMulDown(MathLib.wExp(_err(market).wMulDown(int256(LN2))))))
                    .wDivDown(linearVariation)
            );
        }
        return avgBorrowRate;
    }

    /// @dev Returns the expected `avgBorrowRate` and `baseBorrowRate`.
    function _expectedAvgRate(Market memory market0, Market memory market1) internal view returns (uint256) {
        int256 prevErr = _err(market0);
        int256 err = _err(market1);
        int256 errDelta = err - prevErr;
        uint256 elapsed = block.timestamp - market1.lastUpdate;

        // uint256 jumpMultiplier = MathLib.wExp(errDelta.wMulDown(int256(LN2)));
        uint256 jumpMultiplier =
            MathLib.wExp(-prevErr.wMulDown(int256(LN2))).wMulDown(MathLib.wExp(err.wMulDown(int256(LN2))));
        int256 speed = int256(SPEED_FACTOR).wMulDown(err);
        uint256 variationMultiplier = MathLib.wExp(speed * int256(elapsed));
        uint256 initialRate = INITIAL_BASE_RATE.wMulDown(MathLib.wExp(prevErr.wMulDown(int256(LN2))));
        uint256 expectedBorrowRateAfterJump = initialRate.wMulDown(jumpMultiplier);
        uint256 expectedNewBorrowRate = expectedBorrowRateAfterJump.wMulDown(variationMultiplier);

        uint256 expectedAvgBorrowRate;
        if (speed * int256(elapsed) == 0) {
            expectedAvgBorrowRate = expectedNewBorrowRate;
        } else {
            expectedAvgBorrowRate = uint256(
                (int256(expectedNewBorrowRate) - int256(expectedBorrowRateAfterJump)).wDivDown(speed * int256(elapsed))
            );
        }

        return expectedAvgBorrowRate;
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
