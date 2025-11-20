// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../src/adaptive-curve-irm/AdaptiveCurveIrm.sol";
import "../../src/adaptive-curve-irm/libraries/external/AdaptiveCurveIrmBorrowRateView2Lib.sol";
import "../../lib/forge-std/src/Test.sol";

contract AdaptiveCurveIrmBorrowRateView2LibTest is Test {
    using MarketParamsLib for MarketParams;
    using stdStorage for StdStorage;
    using MathLib for uint256;

    address internal adaptiveCurveIrm;

    function setUp() public {
        adaptiveCurveIrm = address(new AdaptiveCurveIrm(address(this)));
    }

    function testBorrowRateView2(uint256 rateAtTarget, Market memory market) public {
        vm.warp(1000 days);

        vm.assume(rateAtTarget <= uint256(ConstantsLib.MAX_RATE_AT_TARGET));
        // borrow rate doesn't revert on utilization > 1, and the test passes. Still, we require that.
        vm.assume(market.totalBorrowAssets <= market.totalSupplyAssets);
        vm.assume(market.lastUpdate <= 1000 days);
        vm.assume(market.fee < 0.25e18);

        MarketParams memory marketParams;
        marketParams.irm = adaptiveCurveIrm;
        Id id = marketParams.id();

        // set rate at target.
        vm.mockCall(
            adaptiveCurveIrm, abi.encodeWithSelector(IAdaptiveCurveIrm.rateAtTarget.selector), abi.encode(rateAtTarget)
        );
        // compute slot by hand.
        bytes32 slot = keccak256(abi.encode(id, 0));
        vm.store(adaptiveCurveIrm, slot, bytes32(rateAtTarget));
        assertEq(IAdaptiveCurveIrm(adaptiveCurveIrm).rateAtTarget(id), int256(rateAtTarget), "rateAtTarget");

        uint256 computedBorrowRate = AdaptiveCurveIrmBorrowRateView2Lib.borrowRateView2(id, market, adaptiveCurveIrm);
        uint256 expectedBorrowRate = IAdaptiveCurveIrm(adaptiveCurveIrm).borrowRateView(marketParams, market);
        assertEq(computedBorrowRate, expectedBorrowRate, "computedBorrowRate");
    }
}
