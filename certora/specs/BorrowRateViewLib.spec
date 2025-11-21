// SPDX-License-Identifier: GPL-2.0-or-later

using AdaptiveCurveIrm as AdaptiveCurveIrm;
using BorrowRateViewLibWrapper as BorrowRateViewLibWrapper;

methods {
    function BorrowRateViewLibWrapper.toId(AdaptiveCurveIrm.MarketParams) external returns (AdaptiveCurveIrm.Id) envfree;

    function _.rateAtTarget(AdaptiveCurveIrm.Id id) external => DISPATCHER(true);
}

// Rule: borrowRateView2 returns the same result as borrowRateView
rule borrowRateView2Equivalence(env e, AdaptiveCurveIrm.MarketParams marketParams, AdaptiveCurveIrm.Market market) {
    AdaptiveCurveIrm.Id id = BorrowRateViewLibWrapper.toId(marketParams);

    uint256 originalRate = AdaptiveCurveIrm.borrowRateView(e, marketParams, market);
    uint256 view2Rate = BorrowRateViewLibWrapper.borrowRateView2(e, id, market, AdaptiveCurveIrm);

    assert originalRate == view2Rate;
}

// Rule: borrowRateView and borrowRateView2 have the same revert behavior
rule borrowRateView2Liveness(env e, AdaptiveCurveIrm.MarketParams marketParams, AdaptiveCurveIrm.Market market) {
    AdaptiveCurveIrm.Id id = BorrowRateViewLibWrapper.toId(marketParams);

    AdaptiveCurveIrm.borrowRateView@withrevert(e, marketParams, market);
    bool originalReverted = lastReverted;

    BorrowRateViewLibWrapper.borrowRateView2@withrevert(e, id, market, AdaptiveCurveIrm);
    bool view2Reverted = lastReverted;

    assert originalReverted == view2Reverted;
}
