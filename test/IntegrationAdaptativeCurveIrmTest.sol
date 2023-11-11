// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../src/SpeedJumpIrm.sol";
import "../lib/forge-std/src/Test.sol";
import {MathLib as Taylor} from "../lib/morpho-blue/src/libraries/MathLib.sol";
import {BaseTest,IrmMock,IMorpho,MorphoLib} from "../lib/morpho-blue/test/forge/BaseTest.sol";

contract IntegrationAdaptativeCurveIrmTest is BaseTest {
    using MarketParamsLib for MarketParams;
    using MorphoLib for IMorpho;

    int256 internal constant CURVE_STEEPNESS = 4 ether;
    int256 internal constant ADJUSTMENT_SPEED = 50 ether / int256(365 days);
    int256 internal constant TARGET_UTILIZATION = 0.9 ether;
    uint256 internal constant INITIAL_RATE_AT_TARGET = 2 ether / uint256(365 days);

    AdaptativeCurveIrm aIrm;

    function _freshMarket(uint supply, uint borrow) internal returns (MarketParams memory) {
        aIrm =
        new AdaptativeCurveIrm(address(morpho), uint256(CURVE_STEEPNESS), uint256(ADJUSTMENT_SPEED), uint256(TARGET_UTILIZATION), INITIAL_RATE_AT_TARGET);

        marketParams = MarketParams(address(loanToken), address(collateralToken), address(oracle), address(aIrm), DEFAULT_TEST_LLTV);
        id = marketParams.id();

        vm.startPrank(OWNER);
        morpho.enableIrm(address(aIrm));
        morpho.createMarket(marketParams);
        vm.stopPrank();

        // Existing market

        loanToken.setBalance(SUPPLIER,supply);
        vm.prank(SUPPLIER);
        morpho.supply(marketParams, supply, 0, SUPPLIER, hex"");


        collateralToken.setBalance(BORROWER,1e30);
        vm.prank(BORROWER);
        morpho.supplyCollateral(marketParams, 1e30, BORROWER, hex"");
        vm.prank(BORROWER);
        morpho.borrow(marketParams,borrow,0,BORROWER,BORROWER);
        return marketParams;
    }

    // Make stepped accrual fail
    // Will revert due to overflow for a long enough duration
    // Overflow occurs in _accrueInterest when interests are added do supply/borrow assets
    function testSteppedAccrual() public {
        _freshMarket({supply: 1e18, borrow: 0.9e18});
        uint duration = 13 weeks;
        uint period = 1000 seconds;
        for (uint i=0;i<duration/period;i++) {
            _forward(period);
            morpho.accrueInterest(marketParams);
        }
    }

    // Compare stepped accrual (1 accrual per period over duration) vs. leap accrual (1 accrual at end of duration)
    function testCompareAccrualMethods() public {
        // Setup
        uint duration = 9 weeks;
        uint period = 1000 seconds;
        duration = duration-(duration%period); // exact loop iterations for step market

        MarketParams memory stepMarketParams = _freshMarket({supply:1e18, borrow: 0.9e18});
        MarketParams memory leapMarketParams = _freshMarket({supply:1e18, borrow: 0.9e18});

        _forward(1);
        morpho.accrueInterest(stepMarketParams);
        morpho.accrueInterest(leapMarketParams);

        // Same initial borrow for both
        uint initialBorrow = morpho.totalBorrowAssets(stepMarketParams.id());

        // Accrue step market

        for (uint i=0;i<duration/period;i++) {
            _forward(period);
            morpho.accrueInterest(stepMarketParams);
        }

        // Accrue leap market

        morpho.accrueInterest(leapMarketParams);

        // Results

        uint stepFinalBorrow = morpho.totalBorrowAssets(stepMarketParams.id());
        uint leapFinalBorrow = morpho.totalBorrowAssets(leapMarketParams.id());

        console.log("initial borrow      ",initialBorrow);
        console.log("step final borrow   ",stepFinalBorrow);
        console.log("leap final borrow   ",leapFinalBorrow);
        console.log();
        uint stepBorrowIncrease = stepFinalBorrow-initialBorrow;
        uint leapBorrowIncrease = leapFinalBorrow-initialBorrow;
        console.log("step borrow increase",stepBorrowIncrease);
        console.log("leap borrow increase",leapBorrowIncrease);
        console.log();

        console.log("1 block step rate   ",IIrm(irm).borrowRateView(stepMarketParams,morpho.market(stepMarketParams.id())));
        console.log("1 block leap rate   ",IIrm(irm).borrowRateView(leapMarketParams,morpho.market(leapMarketParams.id())));
        console.log();
        console.log("block.number        ",block.number);
        console.log("block.timestamp     ",block.timestamp);

        console.log(unicode"stepΔ/leapΔ          %s%",stepBorrowIncrease*100/leapBorrowIncrease);
    }

    // Compare stepped accrual (1 accrual per period over duration) vs. leap accrual (1 accrual at end of duration)
    function testCompareTaylor() public {
        // Setup
        uint duration = 9 weeks;
        uint period = 1000 seconds;
        duration = duration-(duration%period); // exact loop iterations for step market

        uint init = 10 ether; // init amount
        uint rate = 2 ether / uint256(365 days); // 1%

        uint step;
        uint leap;

        // Leap

        leap = init + Taylor.wMulDown(init, Taylor.wTaylorCompounded(rate, duration));
        console.log("leap",leap);

        // Step

        step = init + Taylor.wMulDown(init, Taylor.wTaylorCompounded(rate, period));

        for (uint i=0;i<duration/period;i++) {
            uint interest = Taylor.wMulDown(step, Taylor.wTaylorCompounded(rate, period));
            // console2.log("interest",interest);
            step += interest;
        }

        console.log("initial      ",rate);
        console.log("step final   ",step);
        console.log("leap final   ",leap);
        console.log();

        uint stepIncrease = step-init;
        uint leapIncrease = leap-init;

        console.log("step increase",stepIncrease);
        console.log("leap increase",leapIncrease);
        console.log();

        console.log();
        console.log("block.number        ",block.number);
        console.log("block.timestamp     ",block.timestamp);

        console.log(unicode"stepΔ/leapΔ          %s%",stepIncrease*100/leapIncrease);

        assertTrue(false);
    }
}
