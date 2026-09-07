// SPDX-License-Identifier: MIT

methods {
    function rateAtTarget(AdaptiveCurveIrmHarness.Id) external returns (int256) envfree;
    function toId(AdaptiveCurveIrmHarness.MarketParams) external returns (AdaptiveCurveIrmHarness.Id) envfree;
    function minRateAtTarget() external returns (int256) envfree;
    function maxRateAtTarget() external returns (int256) envfree;
    function targetUtilization() external returns (int256) envfree;
    function wexpUpperValue() external returns (int256) envfree;

    // The three expensive primitives are over-approximated, each to EXACTLY the range that its own
    // lemma in certora/specs/ExpLibSummary.spec proves, and no more. Which lemma discharges which:
    //   ExpLib.wExp       <- rule wExpTotal      (never reverts)
    //                      + rule wExpBounded    (0 <= wExp(x) <= WEXP_UPPER_VALUE, for every x)
    //   UtilsLib.bound    <- rule boundInRange   (never reverts; low <= high => low <= z <= high)
    //   MathLib.wDivDown  <- rule wDivDownBounded(never reverts; y > 0 && x <= y <= max_uint128
    //                                             => wDivDown(x, y) <= WAD)
    // Replacing a Solidity body with a CVL function also asserts that the callee cannot revert;
    // that half of each summary is the `assert !reverted` of the very same lemma. No clause below
    // is assumed: every one is a proof obligation of a rule that has its own CI job.
    function ExpLib.wExp(int256 x) internal returns (int256) => summaryWExp(x);
    function UtilsLib.bound(int256 x, int256 low, int256 high) internal returns (int256) => summaryBound(x, low, high);
    function MathLib.wDivDown(uint256 x, uint256 y) internal returns (uint256) => summaryWDivDown(x, y);
}

// The value returned by the wDivDown summary, i.e. the utilization computed at
// AdaptiveCurveIrm.sol:79. It is a persistent ghost rather than a fresh local so that the case
// rules can split on the sign of the error term, which AdaptiveCurveIrm.sol:81 and :138 branch on.
persistent ghost uint256 utilizationNondet;

// Safe require, checked by rule wExpBounded in certora/specs/ExpLibSummary.spec.
function summaryWExp(int256 x) returns int256 {
    int256 result;
    require result >= 0 && result <= wexpUpperValue();
    return result;
}

// Safe require, checked by rule boundInRange in certora/specs/ExpLibSummary.spec. The guard
// `low <= high` is the lemma's own precondition; at the single call site
// (AdaptiveCurveIrm.sol:148) low, high are MIN_RATE_AT_TARGET, MAX_RATE_AT_TARGET and MIN < MAX,
// so the guard is concretely true there and nothing is lost.
function summaryBound(int256 x, int256 low, int256 high) returns int256 {
    int256 result;
    require low <= high => (result >= low && result <= high);
    return result;
}

// Safe require, checked by rule wDivDownBounded in certora/specs/ExpLibSummary.spec. The guard is
// that lemma's precondition set; at the single call site (AdaptiveCurveIrm.sol:79) it holds
// because both fields are uint128, the ternary short-circuits on totalSupplyAssets > 0, and
// totalBorrowAssets <= totalSupplyAssets is required below.
function summaryWDivDown(uint256 x, uint256 y) returns uint256 {
    require (y > 0 && x <= y && y <= max_uint128) => utilizationNondet <= 10^18;
    return utilizationNondet;
}

// The fair preconditions shared by every rule below. Each case rule keeps exactly these, and adds
// only a case guard taken from the code's own branch structure.
function fairMarket(env e, AdaptiveCurveIrmHarness.Market market) {
    // borrowRate/borrowRateView are not payable, so a non-zero callvalue is rejected by the
    // compiler-inserted check, not by contract logic.
    require e.msg.value == 0;
    // morpho-blue proves rule noTimeTravel (lib/morpho-blue/certora/specs/ConsistentState.spec).
    require market.lastUpdate <= e.block.timestamp;
    // morpho-blue proves invariant borrowLessThanSupply (lib/morpho-blue/certora/specs/ConsistentState.spec).
    require market.totalBorrowAssets <= market.totalSupplyAssets;
    // Modelling assumption, not backed by a proven invariant: Morpho truncates timestamps to uint128
    // on write (lib/morpho-blue/src/Morpho.sol), and morpho-blue's own specs use the same bound.
    require e.block.timestamp < 2^128;
}

invariant rateAtTargetInRange(AdaptiveCurveIrmHarness.Id id)
    rateAtTarget(id) == 0 ||
    (rateAtTarget(id) >= minRateAtTarget() && rateAtTarget(id) <= maxRateAtTarget());

/* PARENT RULES — the whole statement, no case guard. */

rule borrowRateViewNeverReverts(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    fairMarket(e, market);

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
    fairMarket(e, market);

    borrowRate@withrevert(e, marketParams, market);

    assert !lastReverted;
}

/* CASE RULES.
 *
 * The split follows the branches of AdaptiveCurveIrm._borrowRate. Cases 1-4 cover the whole input
 * space of the parent rules: given lastUpdate <= block.timestamp, either totalSupplyAssets == 0
 * (ZeroSupply), or totalSupplyAssets > 0 and either lastUpdate == block.timestamp (ZeroElapsed) or
 * lastUpdate < block.timestamp, and in the latter case either rateAtTarget(id) == 0
 * (FirstInteraction) or rateAtTarget(id) != 0 (Adapting, split further by the sign of the error
 * term). The cases overlap, which is harmless.
 *
 *   ZeroSupply       - the else branch of the short-circuiting ternary at :79. wDivDown is never
 *                      evaluated, so utilization is the literal 0 and err = -WAD exactly: this is
 *                      also a concretely negative error term, exercising :81's else branch and
 *                      _curve's `err < 0` branch at :138.
 *   ZeroElapsed      - :101 gives elapsed == 0, hence linearAdaptation == 0 at :102, hence the then
 *                      branch at :104. Neither _newRateAtTarget nor wExp is reached.
 *   FirstInteraction - the then branch at :91. speed, elapsed, linearAdaptation, _newRateAtTarget
 *                      and wExp are all unreached; avgRateAtTarget is the constant
 *                      INITIAL_RATE_AT_TARGET.
 *   Adapting*        - the else branch at :108, i.e. the expensive residue: two _newRateAtTarget
 *                      calls at :122-123, each a summarised wExp followed by the summarised clamp.
 *                      PosErr/NegErr split on :81's condition utilization > TARGET_UTILIZATION.
 */

rule borrowRateViewNeverRevertsZeroSupply(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    fairMarket(e, market);
    require market.totalSupplyAssets == 0;

    borrowRateView@withrevert(e, marketParams, market);

    assert !lastReverted;
}

rule borrowRateViewNeverRevertsZeroElapsed(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    fairMarket(e, market);
    require market.totalSupplyAssets > 0;
    require market.lastUpdate == e.block.timestamp;

    borrowRateView@withrevert(e, marketParams, market);

    assert !lastReverted;
}

rule borrowRateViewNeverRevertsFirstInteraction(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    fairMarket(e, market);
    require rateAtTarget(toId(marketParams)) == 0;

    borrowRateView@withrevert(e, marketParams, market);

    assert !lastReverted;
}

rule borrowRateViewNeverRevertsAdaptingPosErr(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    fairMarket(e, market);
    require market.totalSupplyAssets > 0;
    require market.lastUpdate < e.block.timestamp;
    require rateAtTarget(toId(marketParams)) != 0;
    require to_mathint(utilizationNondet) > to_mathint(targetUtilization());

    borrowRateView@withrevert(e, marketParams, market);

    assert !lastReverted;
}

rule borrowRateViewNeverRevertsAdaptingNegErr(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    fairMarket(e, market);
    require market.totalSupplyAssets > 0;
    require market.lastUpdate < e.block.timestamp;
    require rateAtTarget(toId(marketParams)) != 0;
    require to_mathint(utilizationNondet) <= to_mathint(targetUtilization());

    borrowRateView@withrevert(e, marketParams, market);

    assert !lastReverted;
}

rule borrowRateNeverRevertsZeroSupply(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    require e.msg.sender == currentContract.MORPHO;
    fairMarket(e, market);
    require market.totalSupplyAssets == 0;

    borrowRate@withrevert(e, marketParams, market);

    assert !lastReverted;
}

rule borrowRateNeverRevertsZeroElapsed(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    require e.msg.sender == currentContract.MORPHO;
    fairMarket(e, market);
    require market.totalSupplyAssets > 0;
    require market.lastUpdate == e.block.timestamp;

    borrowRate@withrevert(e, marketParams, market);

    assert !lastReverted;
}

rule borrowRateNeverRevertsFirstInteraction(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    require e.msg.sender == currentContract.MORPHO;
    fairMarket(e, market);
    require rateAtTarget(toId(marketParams)) == 0;

    borrowRate@withrevert(e, marketParams, market);

    assert !lastReverted;
}

rule borrowRateNeverRevertsAdaptingPosErr(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    require e.msg.sender == currentContract.MORPHO;
    fairMarket(e, market);
    require market.totalSupplyAssets > 0;
    require market.lastUpdate < e.block.timestamp;
    require rateAtTarget(toId(marketParams)) != 0;
    require to_mathint(utilizationNondet) > to_mathint(targetUtilization());

    borrowRate@withrevert(e, marketParams, market);

    assert !lastReverted;
}

rule borrowRateNeverRevertsAdaptingNegErr(
    env e,
    AdaptiveCurveIrmHarness.MarketParams marketParams,
    AdaptiveCurveIrmHarness.Market market
) {
    requireInvariant rateAtTargetInRange(toId(marketParams));
    require e.msg.sender == currentContract.MORPHO;
    fairMarket(e, market);
    require market.totalSupplyAssets > 0;
    require market.lastUpdate < e.block.timestamp;
    require rateAtTarget(toId(marketParams)) != 0;
    require to_mathint(utilizationNondet) <= to_mathint(targetUtilization());

    borrowRate@withrevert(e, marketParams, market);

    assert !lastReverted;
}
