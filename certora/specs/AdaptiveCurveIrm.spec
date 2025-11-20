// SPDX-License-Identifier: GPL-2.0-or-later

using AdaptiveCurveIrm as AdaptiveCurveIrm;
using BorrowRateView2Wrapper as BorrowRateView2Wrapper;

methods {
    function AdaptiveCurveIrm.borrowRateView(AdaptiveCurveIrm.MarketParams, AdaptiveCurveIrm.Market) external returns (uint256);
    function BorrowRateView2Wrapper.borrowRateView2(AdaptiveCurveIrm.Id, AdaptiveCurveIrm.Market, address) external returns (uint256);
    function BorrowRateView2Wrapper.toId(AdaptiveCurveIrm.MarketParams) external returns (AdaptiveCurveIrm.Id) envfree;

    function _.rateAtTarget(AdaptiveCurveIrm.Id id) external => ghostRateAtTarget expect int256;
}

persistent ghost int256 ghostRateAtTarget;

hook Sload int256 value rateAtTarget[KEY AdaptiveCurveIrm.Id id] {
    require ghostRateAtTarget == value;
}

// Rule: borrowRateView2 returns the same result as borrowRateView
rule borrowRateView2Equivalence(env e, AdaptiveCurveIrm.MarketParams marketParams, AdaptiveCurveIrm.Market market) {
    AdaptiveCurveIrm.Id id = BorrowRateView2Wrapper.toId(marketParams);
    
    uint256 originalRate = AdaptiveCurveIrm.borrowRateView(e, marketParams, market);
    uint256 view2Rate = BorrowRateView2Wrapper.borrowRateView2(e, id, market, AdaptiveCurveIrm);
    
    assert originalRate == view2Rate;
}
