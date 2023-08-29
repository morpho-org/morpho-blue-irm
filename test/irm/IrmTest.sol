// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/irm/Irm.sol";

contract IrmTest is Test {
    using MathLib for uint128;
    using MathLib for uint256;
    using MarketParamsLib for MarketParams;

    uint256 internal constant SPEED = 0.01 ether;
    uint256 internal constant LN2 = 0.69314718056 ether;
    uint256 internal constant TARGET_UTILIZATION = 0.8 ether;
    uint256 internal constant INITIAL_RATE = uint256(0.01 ether) / uint256(365 days);

    Irm internal irm;

    constructor() {
        irm = new Irm(address(this), LN2, SPEED, TARGET_UTILIZATION, INITIAL_RATE);
    }

    function testFirstBorrowRate(MarketParams memory marketParams, Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);
        vm.assume(market.lastUpdate >= block.timestamp);
        vm.assume(market.lastUpdate < type(uint32).max);
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
        vm.assume(market.lastUpdate >= block.timestamp);
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
        vm.assume(market0.lastUpdate >= block.timestamp);
        vm.assume(market0.lastUpdate < type(uint32).max);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        vm.assume(market1.lastUpdate > market0.lastUpdate);
        vm.assume(market1.lastUpdate < type(uint32).max);
        uint256 elapsed = market1.lastUpdate - market0.lastUpdate;
        vm.assume(elapsed * WAD / 365 days < 1 ether);
        uint256 avgBorrowRate = irm.borrowRate(marketParams, market1);

        uint256 utilization0 = market0.totalBorrowAssets.wDivDown(market0.totalSupplyAssets);
        uint256 utilization1 = market1.totalBorrowAssets.wDivDown(market1.totalSupplyAssets);
        (uint256 prevBorrowRate, uint256 prevUtilization) = irm.marketIrm(marketParams.id());
        assertEq(prevUtilization, utilization1);

        if (utilization0 <= utilization1 && utilization1 >= TARGET_UTILIZATION) {
            assertGe(avgBorrowRate, INITIAL_RATE);
            assertGe(prevBorrowRate, INITIAL_RATE);
        } else if (utilization0 >= utilization1 && utilization1 < TARGET_UTILIZATION) {
            assertLt(avgBorrowRate, INITIAL_RATE);
            assertLt(prevBorrowRate, INITIAL_RATE);
        }
    }

    function testBorrowRateView(MarketParams memory marketParams, Market memory market0, Market memory market1)
        public
    {
        vm.assume(market0.totalBorrowAssets > 0);
        vm.assume(market0.totalSupplyAssets >= market0.totalBorrowAssets);
        vm.assume(market0.lastUpdate >= block.timestamp);
        vm.assume(market0.lastUpdate < type(uint32).max);
        irm.borrowRate(marketParams, market0);

        vm.assume(market1.totalBorrowAssets > 0);
        vm.assume(market1.totalSupplyAssets >= market1.totalBorrowAssets);
        vm.assume(market1.lastUpdate > market0.lastUpdate);
        vm.assume(market1.lastUpdate < type(uint32).max);
        uint256 elapsed = market1.lastUpdate - market0.lastUpdate;
        vm.assume(elapsed * WAD / 365 days < 1 ether);
        uint256 avgBorrowRate = irm.borrowRateView(marketParams, market1);

        uint256 utilization0 = market0.totalBorrowAssets.wDivDown(market0.totalSupplyAssets);
        uint256 utilization1 = market1.totalBorrowAssets.wDivDown(market1.totalSupplyAssets);
        (uint256 prevBorrowRate, uint256 prevUtilization) = irm.marketIrm(marketParams.id());
        assertEq(prevUtilization, utilization0);
        assertEq(prevBorrowRate, INITIAL_RATE);

        if (utilization0 <= utilization1 && utilization1 >= TARGET_UTILIZATION) {
            assertGe(avgBorrowRate, INITIAL_RATE);
        } else if (utilization0 >= utilization1 && utilization1 < TARGET_UTILIZATION) {
            assertLt(avgBorrowRate, INITIAL_RATE);
        }
    }
}
