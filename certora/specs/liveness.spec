// SPDX-License-Identifier: UNLICENCED
methods {
    function borrowRateView(Irm.MarketParams, Irm.Market) external returns uint256 envfree;
    function borrowRate(Irm.MarketParams, Irm.Market) external returns uint256 envfree;
}

rule borrowRateNeverReverts(env e, Irm.MarketParams marketParams, Irm.Market market) {
    borrowRate@withrevert(e, marketParams, market);
    assert false;
}
