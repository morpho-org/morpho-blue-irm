// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../src/fixed-rate-irm/FixedRateIrm.sol";

import "../../lib/forge-std/src/Test.sol";

contract FixedRateIrmTest is Test {
    using MarketParamsLib for MarketParams;

    event SetBorrowRate(Id indexed id, uint256 newBorrowRate);

    FixedRateIrm public fixedRateIrm;

    function setUp() external {
        fixedRateIrm = new FixedRateIrm();
    }

    function testSetBorrowRate(Id id, uint256 newBorrowRate) external {
        vm.assume(newBorrowRate != 0);

        fixedRateIrm.setBorrowRate(id, newBorrowRate);
        assertEq(fixedRateIrm.borrowRateStored(id), newBorrowRate);
    }

    function testSetBorrowRateEvent(Id id, uint256 newBorrowRate) external {
        vm.assume(newBorrowRate != 0);

        vm.expectEmit(true, true, true, true, address(fixedRateIrm));
        emit SetBorrowRate(id, newBorrowRate);
        fixedRateIrm.setBorrowRate(id, newBorrowRate);
    }

    function testSetBorrowRateAlreadySet(Id id, uint256 newBorrowRate1, uint256 newBorrowRate2) external {
        vm.assume(newBorrowRate1 != 0);
        vm.assume(newBorrowRate2 != 0);
        fixedRateIrm.setBorrowRate(id, newBorrowRate1);
        vm.expectRevert(bytes(RATE_SET));
        fixedRateIrm.setBorrowRate(id, newBorrowRate2);
    }

    function testSetBorrowRateRateZero(Id id) external {
        vm.expectRevert(bytes(RATE_ZERO));
        fixedRateIrm.setBorrowRate(id, 0);
    }

    function testBorrowRate(MarketParams memory marketParams, Market memory market, uint256 newBorrowRate) external {
        vm.assume(newBorrowRate != 0);
        fixedRateIrm.setBorrowRate(marketParams.id(), newBorrowRate);
        assertEq(fixedRateIrm.borrowRate(marketParams, market), newBorrowRate);
    }

    function testBorrowRateRateNotSet(MarketParams memory marketParams, Market memory market) external {
        vm.expectRevert(bytes(RATE_NOT_SET));
        fixedRateIrm.borrowRate(marketParams, market);
    }

    function testBorrowRateView(MarketParams memory marketParams, Market memory market, uint256 newBorrowRate)
        external
    {
        vm.assume(newBorrowRate != 0);
        fixedRateIrm.setBorrowRate(marketParams.id(), newBorrowRate);
        assertEq(fixedRateIrm.borrowRateView(marketParams, market), newBorrowRate);
    }

    function testBorrowRateViewRateNotSet(MarketParams memory marketParams, Market memory market) external {
        vm.expectRevert(bytes(RATE_NOT_SET));
        fixedRateIrm.borrowRateView(marketParams, market);
    }
}
