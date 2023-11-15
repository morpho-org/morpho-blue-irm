// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../src/SpeedJumpIrm.sol";
import "../lib/forge-std/src/Test.sol";
import {BaseTest, IrmMock, IMorpho, MorphoLib} from "../lib/morpho-blue/test/forge/BaseTest.sol";

contract IntegrationAdaptativeCurveIrmTest is BaseTest {
    using MarketParamsLib for MarketParams;
    using MorphoLib for IMorpho;

    int256 internal constant CURVE_STEEPNESS = 4 ether;
    int256 internal constant ADJUSTMENT_SPEED = 50 ether / int256(365 days);
    int256 internal constant TARGET_UTILIZATION = 0.9 ether;
    uint256 internal constant INITIAL_RATE_AT_TARGET = 2 ether / uint256(365 days);

    AdaptativeCurveIrm aIrm;

    function _freshMarket(uint256 supply, uint256 borrow) internal returns (MarketParams memory) {
        aIrm =
        new AdaptativeCurveIrm(address(morpho), uint256(CURVE_STEEPNESS), uint256(ADJUSTMENT_SPEED), uint256(TARGET_UTILIZATION), INITIAL_RATE_AT_TARGET);

        marketParams = MarketParams(
            address(loanToken), address(collateralToken), address(oracle), address(aIrm), DEFAULT_TEST_LLTV
        );
        id = marketParams.id();

        vm.startPrank(OWNER);
        morpho.enableIrm(address(aIrm));
        morpho.createMarket(marketParams);
        vm.stopPrank();

        // Existing market

        loanToken.setBalance(SUPPLIER, supply);
        vm.prank(SUPPLIER);
        morpho.supply(marketParams, supply, 0, SUPPLIER, hex"");

        collateralToken.setBalance(BORROWER, 1e30);
        vm.prank(BORROWER);
        morpho.supplyCollateral(marketParams, 1e30, BORROWER, hex"");
        vm.prank(BORROWER);
        morpho.borrow(marketParams, borrow, 0, BORROWER, BORROWER);
        return marketParams;
    }

    // Make stepped accrual fail
    // Will revert due to overflow for a long enough duration
    // Overflow occurs in _accrueInterest when interests are added to supply/borrow assets
    function testSteppedAccrual() public {
        _freshMarket({supply: 1e18, borrow: 0.9e18});
        uint256 duration = 1000 weeks;
        uint256 period = 1000 seconds;
        uint256 borrow = morpho.totalBorrowAssets(id);
        uint256 refRate = INITIAL_RATE_AT_TARGET;
        uint256 refI;
        for (uint256 i = 0; i < duration / period; i++) {
            _forward(period);
            morpho.accrueInterest(marketParams);
            uint256 nextStepBorrow = morpho.totalBorrowAssets(id);
            uint256 rate = (nextStepBorrow - borrow) / 1000;
            borrow = nextStepBorrow;
            if (rate > 2 * refRate) {
                // `(i - refI) * 1000` is the time elapsed to double the rate
                console.log(((i - refI) * 1000 * 100) / (1 days));
                refRate = rate;
                refI = i;
            }
        }
    }

    // Compare stepped accrual (1 accrual per period over duration) vs. leap accrual (1 accrual at end of duration)
    function testCompareAccrualMethods() public {
        // Setup
        uint256 duration = 9 weeks;
        uint256 period = 1000 seconds;
        duration = duration - (duration % period); // exact loop iterations for step market

        MarketParams memory stepMarketParams = _freshMarket({supply: 1e18, borrow: 0.9e18});
        MarketParams memory leapMarketParams = _freshMarket({supply: 1e18, borrow: 0.9e18});

        _forward(1);
        morpho.accrueInterest(stepMarketParams);
        morpho.accrueInterest(leapMarketParams);

        // Same initial borrow for both
        uint256 initialBorrow = morpho.totalBorrowAssets(stepMarketParams.id());

        // Accrue step market

        for (uint256 i = 0; i < duration / period; i++) {
            _forward(period);
            morpho.accrueInterest(stepMarketParams);
        }

        // Accrue leap market

        morpho.accrueInterest(leapMarketParams);

        // Results

        uint256 stepFinalBorrow = morpho.totalBorrowAssets(stepMarketParams.id());
        uint256 leapFinalBorrow = morpho.totalBorrowAssets(leapMarketParams.id());

        console.log("initial borrow      ", initialBorrow);
        console.log("step final borrow   ", stepFinalBorrow);
        console.log("leap final borrow   ", leapFinalBorrow);
        console.log();
        uint256 stepBorrowIncrease = stepFinalBorrow - initialBorrow;
        uint256 leapBorrowIncrease = leapFinalBorrow - initialBorrow;
        console.log("step borrow increase", stepBorrowIncrease);
        console.log("leap borrow increase", leapBorrowIncrease);
        console.log();

        console.log(
            "1 block step rate   ", IIrm(irm).borrowRateView(stepMarketParams, morpho.market(stepMarketParams.id()))
        );
        console.log(
            "1 block leap rate   ", IIrm(irm).borrowRateView(leapMarketParams, morpho.market(leapMarketParams.id()))
        );
        console.log();
        console.log("block.number        ", block.number);
        console.log("block.timestamp     ", block.timestamp);

        console.log(unicode"stepΔ/leapΔ          %s%", stepBorrowIncrease * 100 / leapBorrowIncrease);
    }
}
