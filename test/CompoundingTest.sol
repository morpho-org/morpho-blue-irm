// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../lib/morpho-blue/test/forge/BaseTest.sol";

import {SpeedJumpIrm} from "../src/SpeedJumpIrm.sol";

contract CompoundingTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using SharesMathLib for uint256;
    using MarketParamsLib for MarketParams;

    uint256 internal constant LN2 = 0.69314718056 ether;
    uint256 internal constant TARGET_UTILIZATION = 0.8 ether;
    uint256 internal constant SPEED_FACTOR = uint256(0.01 ether) / uint256(10 hours);
    uint128 internal constant INITIAL_RATE = uint128(0.01 ether) / uint128(365 days);

    function _setIrm(address _irm) internal {
        irm = IrmMock(_irm);
        marketParams = MarketParams(
            address(loanToken), address(collateralToken), address(oracle), address(_irm), marketParams.lltv
        );
        id = marketParams.id();

        vm.startPrank(OWNER);
        morpho.enableIrm(address(irm));
        if (morpho.lastUpdate(marketParams.id()) == 0) morpho.createMarket(marketParams);
        vm.stopPrank();

        _forward(1);
    }

    function testCompounding() public {
        SpeedJumpIrm sjIRM = new SpeedJumpIrm(address(morpho), LN2, SPEED_FACTOR, TARGET_UTILIZATION, INITIAL_RATE);
        _setIrm(address(sjIRM));

        console.log("marketParams.lltv", marketParams.lltv);

        _supply(1000 ether);

        uint256 amountBorrowed = 0;
        uint256 amountCollateral = 0;

        amountCollateral = 100 ether;
        amountBorrowed = amountCollateral.mulDivDown(oracle.price(), ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv);

        vm.startPrank(BORROWER);
        collateralToken.setBalance(BORROWER, amountCollateral);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        uint256 totalBorrowAssetsStart = morpho.totalBorrowAssets(id);

        uint256 initialTS = block.timestamp;
        console.log("initialTS", initialTS);
        uint256 snapshotId = vm.snapshot();

        // [OPTIONAL] uncomment for two interactions
        // vm.warp(block.timestamp + 1 days);
        // vm.roll(block.number + 1);
        // vm.startPrank(LIQUIDATOR);
        // collateralToken.setBalance(LIQUIDATOR, 1);
        // morpho.supplyCollateral(marketParams, 1, LIQUIDATOR, hex"");
        // morpho.withdrawCollateral(marketParams, 1, LIQUIDATOR, LIQUIDATOR);
        // vm.stopPrank();

        // warp 1 year and see how the supply has changed
        // [OPTIONAL] change 365 into 364 in case of 2 interactions
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);

        console.log("before accrual", morpho.totalBorrowAssets(id));
        console.log("USED AVG BORROW RATE");
        // trigger the accrual
        vm.startPrank(LIQUIDATOR);
        collateralToken.setBalance(LIQUIDATOR, 1);
        morpho.supplyCollateral(marketParams, 1, LIQUIDATOR, hex"");
        morpho.withdrawCollateral(marketParams, 1, LIQUIDATOR, LIQUIDATOR);
        vm.stopPrank();
        console.log("END USED AVG RATE");

        uint256 totalBorrowAssetsEndOneYearSingleJump = morpho.totalBorrowAssets(id);
        console.log("totalBorrowAssetsStart", totalBorrowAssetsStart);
        console.log("totalBorrowAssetsEndOneYearSingleJump", totalBorrowAssetsEndOneYearSingleJump);
        console.log("delta IR 1 year, single jump", totalBorrowAssetsEndOneYearSingleJump - totalBorrowAssetsStart);
        console.log("day passed", (block.timestamp - initialTS) / 1 days);

        // revert snapshot
        vm.revertTo(snapshotId);
        // iterate for 365 days
        for (uint256 i = 0; i < 365; i++) {
            // [OPTIONAL] Rate goes down rapidly to the min rate
            // if (i % 40 == 0) {
            //     console.log();
            //     console.log(sjIRM.MIN_RATE());
            //     console.log(sjIRM.borrowRateView(marketParams, morpho.getMarket(id)));
            // }
            vm.warp(block.timestamp + 1 days);
            vm.roll(block.number + 1);

            // trigger the accrual
            vm.startPrank(LIQUIDATOR);
            collateralToken.setBalance(LIQUIDATOR, 1);
            morpho.supplyCollateral(marketParams, 1, LIQUIDATOR, hex"");
            morpho.withdrawCollateral(marketParams, 1, LIQUIDATOR, LIQUIDATOR);
            vm.stopPrank();
        }
        uint256 totalBorrowAssetsEndOneYearMultipleJump = morpho.totalBorrowAssets(id);

        console.log("totalBorrowAssetsStart", totalBorrowAssetsStart);
        console.log("totalBorrowAssetsEndOneYearMultipleJump", totalBorrowAssetsEndOneYearMultipleJump);
        console.log("delta IR 1 year, multiple jump", totalBorrowAssetsEndOneYearMultipleJump - totalBorrowAssetsStart);
        console.log("day passed", (block.timestamp - initialTS) / 1 days);

        if (totalBorrowAssetsEndOneYearSingleJump > totalBorrowAssetsEndOneYearMultipleJump) {
            console.log("totalBorrowAssetsEndOneYearMultipleJump < totalBorrowAssetsEndOneYearSingleJump");
            console.log(
                "Delta multiple jump - single jump",
                totalBorrowAssetsEndOneYearSingleJump - totalBorrowAssetsEndOneYearMultipleJump
            );
        }
    }
}
