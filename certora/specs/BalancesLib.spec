// SPDX-License-Identifier: GPL-2.0-or-later

using AdaptiveCurveIrm as AdaptiveCurveIrm;
using BalancesLibWrapper as BalancesLibWrapper;
using Morpho as Morpho;

methods {
    function BalancesLibWrapper.toId(AdaptiveCurveIrm.MarketParams) external returns (AdaptiveCurveIrm.Id) envfree;

    function _.rateAtTarget(AdaptiveCurveIrm.Id id) external => DISPATCHER(true);
    function _.market(Morpho.Id) external => DISPATCHER(true);
    function _.borrowRateView(Morpho.MarketParams, Morpho.Market) external => DISPATCHER(true);
}

// Rule: AdaptiveCurveIrmBalancesLib behaves identically to MorphoBalancesLib
rule balancesLibEquivalence(env e, address morpho, AdaptiveCurveIrm.MarketParams marketParams) {
    require marketParams.irm == AdaptiveCurveIrm;

    AdaptiveCurveIrm.Id id = BalancesLibWrapper.toId(marketParams);

    // Get results from both libraries
    uint256 adaptiveTotalSupplyAssets;
    uint256 adaptiveTotalSupplyShares;
    uint256 adaptiveTotalBorrowAssets;
    uint256 adaptiveTotalBorrowShares;
    (adaptiveTotalSupplyAssets, adaptiveTotalSupplyShares, adaptiveTotalBorrowAssets, adaptiveTotalBorrowShares) =
        BalancesLibWrapper.adaptiveCurveIrmExpectedMarketBalances(e, morpho, id, AdaptiveCurveIrm);

    uint256 morphoTotalSupplyAssets;
    uint256 morphoTotalSupplyShares;
    uint256 morphoTotalBorrowAssets;
    uint256 morphoTotalBorrowShares;
    (morphoTotalSupplyAssets, morphoTotalSupplyShares, morphoTotalBorrowAssets, morphoTotalBorrowShares) =
        BalancesLibWrapper.morphoExpectedMarketBalances(e, morpho, marketParams);

    // Both libraries should return identical results
    assert adaptiveTotalSupplyAssets == morphoTotalSupplyAssets;
    assert adaptiveTotalSupplyShares == morphoTotalSupplyShares;
    assert adaptiveTotalBorrowAssets == morphoTotalBorrowAssets;
    assert adaptiveTotalBorrowShares == morphoTotalBorrowShares;
}

rule balancesLibLiveness(env e, address morpho, AdaptiveCurveIrm.MarketParams marketParams) {
    require marketParams.irm == AdaptiveCurveIrm;

    AdaptiveCurveIrm.Id id = BalancesLibWrapper.toId(marketParams);

    BalancesLibWrapper.adaptiveCurveIrmExpectedMarketBalances@withrevert(e, morpho, id, AdaptiveCurveIrm);
    bool adaptiveCurveIrmReverted = lastReverted;

    BalancesLibWrapper.morphoExpectedMarketBalances@withrevert(e, morpho, marketParams);
    bool morphoReverted = lastReverted;

    assert adaptiveCurveIrmReverted == morphoReverted;
}
