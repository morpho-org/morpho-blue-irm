// SPDX-License-Identifier: UNLICENCED
methods {
    function MORPHO() external returns address envfree;
}

rule borrowRateNeverReverts(env e, Irm.MarketParams marketParams, Irm.Market market) {
    require e.msg.sender == MORPHO();
    require e.msg.value == 0;

    borrowRate@withrevert(e, marketParams, market);

    assert !lastReverted;
}
