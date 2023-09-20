// SPDX-License-Identifier: UNLICENCED
methods {
    function MORPHO() external returns address envfree;
    function TARGET_UTILIZATION() external returns uint256 envfree;
}

definition WAD() returns uint256 = 10^18;

invariant maxTargetUtilization()
    TARGET_UTILIZATION() <= WAD();

rule borrowRateNeverReverts(env e, Irm.MarketParams marketParams, Irm.Market market) {
    require e.msg.sender == MORPHO();
    require e.msg.value == 0;
    requireInvariant maxTargetUtilization();

    borrowRate@withrevert(e, marketParams, market);

    assert !lastReverted;
}
