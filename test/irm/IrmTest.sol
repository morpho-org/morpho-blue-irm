// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/irm/Irm.sol";

contract IrmTest is Test {
    Irm irm;

    constructor() {
        irm = new Irm(address(this), WAD, WAD, 0.8 ether);
    }

    function testFirstBorrowRate(MarketParams memory marketParams, Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);
        vm.assume(market.lastUpdate >= block.timestamp);
        vm.assume(market.lastUpdate < type(uint32).max);
        uint256 borrowRate = irm.borrowRate(marketParams, market);
        assertEq(borrowRate, WAD);
    }

    function testFirstBorrowRateView(MarketParams memory marketParams, Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);
        vm.assume(market.lastUpdate >= block.timestamp);
        vm.assume(market.lastUpdate < type(uint32).max);
        uint256 borrowRate = irm.borrowRateView(marketParams, market);
        assertEq(borrowRate, 0);
    }
}
