// SPDX-License-Identifier: MIT

methods {
    function rateAtTarget(AdaptiveCurveIrmHarness.Id) external returns (int256) envfree;
    function toId(AdaptiveCurveIrmHarness.MarketParams) external returns (AdaptiveCurveIrmHarness.Id) envfree;
    function minRateAtTarget() external returns (int256) envfree;
    function maxRateAtTarget() external returns (int256) envfree;
    function wexpUpperValue() external returns (int256) envfree;

    function ExpLib.wExp(int256 x) internal returns (int256) => summaryWExp(x);
    function UtilsLib.bound(int256 x, int256 low, int256 high) internal returns (int256) => summaryBound(x, low, high);
    function MathLib.wDivDown(uint256 x, uint256 y) internal returns (uint256) => summaryWDivDown(x, y);
}

// Safe require, checked by rule wExpBounded in certora/specs/ExpLibSummary.spec.
function summaryWExp(int256 x) returns int256 {
    int256 result;
    require result >= 0 && result <= wexpUpperValue();
    return result;
}

// Safe require, checked by rule boundInRange in certora/specs/ExpLibSummary.spec.
function summaryBound(int256 x, int256 low, int256 high) returns int256 {
    int256 result;
    require low <= high => (result >= low && result <= high);
    return result;
}

// Safe require, checked by rule wDivDownBounded in certora/specs/ExpLibSummary.spec.
function summaryWDivDown(uint256 x, uint256 y) returns uint256 {
    uint256 result;
    require (y > 0 && x <= y && y <= max_uint128) => result <= 10^18;
    return result;
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
    // borrowRate and borrowRateView are not payable.
    require e.msg.value == 0;
    // morpho-blue proves rule noTimeTravel (lib/morpho-blue/certora/specs/ConsistentState.spec).
    require market.lastUpdate <= e.block.timestamp;
    // morpho-blue proves invariant borrowLessThanSupply (lib/morpho-blue/certora/specs/ConsistentState.spec).
    require market.totalBorrowAssets <= market.totalSupplyAssets;
    // Morpho truncates timestamps to uint128 on write (lib/morpho-blue/src/Morpho.sol).
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
    // borrowRate and borrowRateView are not payable.
    require e.msg.value == 0;
    // morpho-blue proves rule noTimeTravel (lib/morpho-blue/certora/specs/ConsistentState.spec).
    require market.lastUpdate <= e.block.timestamp;
    // morpho-blue proves invariant borrowLessThanSupply (lib/morpho-blue/certora/specs/ConsistentState.spec).
    require market.totalBorrowAssets <= market.totalSupplyAssets;
    // Morpho truncates timestamps to uint128 on write (lib/morpho-blue/src/Morpho.sol).
    require e.block.timestamp < 2^128;
    // AdaptiveCurveIrm.sol:60 rejects every caller other than MORPHO.
    require e.msg.sender == currentContract.MORPHO;

    borrowRate@withrevert(e, marketParams, market);

    assert !lastReverted;
}
