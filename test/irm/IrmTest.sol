// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/irm/Irm.sol";

contract IrmTest is Test {
    using MathLib for uint128;
    using MathLib for uint256;
    using MarketParamsLib for MarketParams;

    Irm irm;

    uint256 constant ln2 = 0.69314718056 ether;

    constructor() {
        irm = new Irm(address(this), ln2, WAD / 365 days, 0.8 ether);
    }

    function testFirstBorrowRate(MarketParams memory marketParams, Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);
        vm.assume(market.lastUpdate >= block.timestamp);
        vm.assume(market.lastUpdate < type(uint32).max);
        uint256 borrowRate = irm.borrowRate(marketParams, market);
        uint256 expectedUtilization = market.totalBorrowAssets.wDivDown(market.totalSupplyAssets);
        assertEq(borrowRate, WAD);
        assertEq(irm.prevBorrowRate(marketParams.id()), WAD);
        assertEq(uint256(irm.prevUtilization(marketParams.id())), expectedUtilization);
    }

    function testFirstBorrowRateView(MarketParams memory marketParams, Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);
        vm.assume(market.lastUpdate >= block.timestamp);
        vm.assume(market.lastUpdate < type(uint32).max);
        uint256 borrowRate = irm.borrowRateView(marketParams, market);
        assertEq(borrowRate, WAD);
        assertEq(irm.prevBorrowRate(marketParams.id()), 0);
        assertEq(irm.prevUtilization(marketParams.id()), 0);
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
        irm.borrowRate(marketParams, market1);

        uint256 utilization0 = market0.totalBorrowAssets.wDivDown(market0.totalSupplyAssets);
        uint256 utilization1 = market1.totalBorrowAssets.wDivDown(market1.totalSupplyAssets);
        assertEq(uint256(irm.prevUtilization(marketParams.id())), utilization1);

        if (utilization0 <= utilization1 && utilization1 >= 0.8 ether) {
            assertGe(irm.prevBorrowRate(marketParams.id()), WAD);
        } else if (utilization0 > utilization1 && utilization1 < 0.8 ether) {
            assertLt(irm.prevBorrowRate(marketParams.id()), WAD);
        }
    }

    function testWPow(int256 x) public {
        assertApproxEqRel(wFloatPow(ln2, -1 ether), 0.5 ether, 0.02 ether);
        assertApproxEqRel(wFloatPow(ln2, -0.5 ether), 0.70710678118 ether, 0.01 ether);
        assertEq(wFloatPow(ln2, 0), 1 ether);
        assertApproxEqRel(wFloatPow(ln2, 0.5 ether), 1.41421356237 ether, 0.01 ether);
        assertApproxEqRel(wFloatPow(ln2, 1 ether), 2 ether, 0.02 ether);

        x = bound(x, -1 ether, 1 ether);
        wFloatPow(ln2, x);
    }

    function testWExp(int256 x) public {
        assertApproxEqRel(wExp(-1 ether), 0.36787944117 ether, 0.1 ether);
        assertApproxEqRel(wExp(-0.1 ether), 0.90483741803 ether, 0.01 ether);
        assertEq(wExp(0 ether), 1 ether);
        assertApproxEqRel(wExp(0.1 ether), 1.10517091808 ether, 0.01 ether);
        assertApproxEqRel(wExp(1 ether), 2.71828182846 ether, 0.1 ether);

        x = bound(x, -1 ether, 1 ether);
        assertGe(wExp(x), uint256(int256(WAD) + x));

        if (x < 0) assertLt(wExp(x), WAD);
        else assertGe(wExp(x), WAD);
    }
}
