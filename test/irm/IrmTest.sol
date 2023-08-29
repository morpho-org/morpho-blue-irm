// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/irm/Irm.sol";

contract IrmTest is Test {
    using MathLib for uint128;
    using MathLib for uint256;
    using MarketParamsLib for MarketParams;

    uint256 internal constant LN2 = 0.69314718056 ether;
    uint256 internal constant TARGET_UTILIZATION = 0.8 ether;
    uint256 internal constant SPEED = uint256(0.01 ether) / uint256(10 hours);
    uint256 internal constant INITIAL_RATE = uint256(0.01 ether) / uint256(365 days);

    Irm internal irm;

    constructor() {
        irm = new Irm(address(this), LN2, SPEED, TARGET_UTILIZATION, INITIAL_RATE);
        vm.warp(90 days);
    }

    function testFirstBorrowRate(MarketParams memory marketParams, Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);
        market.lastUpdate = uint128(bound(market.lastUpdate, 0, block.timestamp - 1));
        uint256 avgBorrowRate = irm.borrowRate(marketParams, market);
        assertEq(avgBorrowRate, INITIAL_RATE);
        uint256 expectedUtilization = market.totalBorrowAssets.wDivDown(market.totalSupplyAssets);
        (uint256 prevBorrowRate, uint256 prevUtilization) = irm.marketIrm(marketParams.id());
        assertEq(prevBorrowRate, INITIAL_RATE);
        assertEq(prevUtilization, expectedUtilization);
    }

    function testFirstBorrowRateView(MarketParams memory marketParams, Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);
        market.lastUpdate = uint128(bound(market.lastUpdate, 0, block.timestamp - 1));
        vm.assume(market.lastUpdate < type(uint32).max);
        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market);
        assertEq(avgBorrowRate, INITIAL_RATE);
        (uint256 prevBorrowRate, uint256 prevUtilization) = irm.marketIrm(marketParams.id());
        assertEq(prevBorrowRate, 0);
        assertEq(prevUtilization, 0);
    }

    function testBorrowRate(MarketParams memory marketParams, Market memory market0, Market memory market1) public {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        market0.lastUpdate = uint128(bound(market0.lastUpdate, 0, block.timestamp - 1));
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

    function testBorrowRateView(MarketParams memory marketParams, Market memory market0, Market memory market1)
        public
    {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        market0.lastUpdate = uint128(bound(market0.lastUpdate, 0, block.timestamp - 1));
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
}
