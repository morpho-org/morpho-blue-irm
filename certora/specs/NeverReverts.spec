// SPDX-License-Identifier: MIT

methods {
    function rateAtTarget(AdaptiveCurveIrmHarness.Id) external returns (int256) envfree;
    function toId(AdaptiveCurveIrmHarness.MarketParams) external returns (AdaptiveCurveIrmHarness.Id) envfree;
    function minRateAtTarget() external returns (int256) envfree;
    function maxRateAtTarget() external returns (int256) envfree;
}

invariant rateAtTargetInRange(AdaptiveCurveIrmHarness.Id id)
    rateAtTarget(id) == 0 ||
    (rateAtTarget(id) >= minRateAtTarget() && rateAtTarget(id) <= maxRateAtTarget());

rule borrowRateViewNeverReverts(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));

    // borrowRateView is not payable, so a non-zero callvalue is rejected by the compiler-inserted check.
    require e.msg.value == 0;
    // morpho-blue proves rule noTimeTravel (certora/specs/ConsistentState.spec), so lastUpdate <= block.timestamp.
    require market.lastUpdate <= e.block.timestamp;
    // morpho-blue proves invariant borrowLessThanSupply (certora/specs/ConsistentState.spec).
    require market.totalBorrowAssets <= market.totalSupplyAssets;
    // Modelling assumption, not backed by a proven invariant: Morpho truncates timestamps to uint128 on write
    // (lib/morpho-blue/src/Morpho.sol), and morpho-blue's own specs use the same bound.
    require e.block.timestamp < 2^128;

    borrowRateView@withrevert(e, marketParams, market);

    assert !lastReverted;
}

rule borrowRateNeverReverts(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));

    // AdaptiveCurveIrm.sol:60 requires the caller to be MORPHO; that revert is intentional.
    require e.msg.sender == currentContract.MORPHO;
    // borrowRate is not payable, so a non-zero callvalue is rejected by the compiler-inserted check.
    require e.msg.value == 0;
    // morpho-blue proves rule noTimeTravel (certora/specs/ConsistentState.spec), so lastUpdate <= block.timestamp.
    require market.lastUpdate <= e.block.timestamp;
    // morpho-blue proves invariant borrowLessThanSupply (certora/specs/ConsistentState.spec).
    require market.totalBorrowAssets <= market.totalSupplyAssets;
    // Modelling assumption, not backed by a proven invariant: Morpho truncates timestamps to uint128 on write
    // (lib/morpho-blue/src/Morpho.sol), and morpho-blue's own specs use the same bound.
    require e.block.timestamp < 2^128;

    borrowRate@withrevert(e, marketParams, market);

    assert !lastReverted;
}
