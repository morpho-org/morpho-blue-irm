// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function rateAtTarget(AdaptiveCurveIrm.Id id) external returns (int256) envfree;
    function MORPHO() external returns (address) envfree;
    function Utils.toId(AdaptiveCurveIrm.MarketParams) external returns (AdaptiveCurveIrm.Id) envfree;
}

rule borrowRateNeverReverts(env e, AdaptiveCurveIrm.MarketParams marketParams, AdaptiveCurveIrm.Market market) {
    AdaptiveCurveIrm.Id id = Utils.toId(marketParams);

    require rateAtTarget(id) >= 0;
    require rateAtTarget(id) <= 63419583967;
    require e.msg.sender == MORPHO();
    require e.msg.value == 0;
    require market.lastUpdate <= e.block.timestamp;
    require market.lastUpdate >= e.block.timestamp - 200 * (365 * 24 * 60 * 60);

    borrowRate@withrevert(e, marketParams, market);
    assert !lastReverted;
}
