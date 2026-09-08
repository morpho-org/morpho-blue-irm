// SPDX-License-Identifier: MIT

methods {
    function wExpExt(int256) external returns (int256) envfree;
    function boundExt(int256, int256, int256) external returns (int256) envfree;
    function curveExt(int256, int256) external returns (int256) envfree;
    function newRateAtTargetExt(int256, int256) external returns (int256) envfree;
    function wDivDownExt(uint256, uint256) external returns (uint256) envfree;
    function minRateAtTarget() external returns (int256) envfree;
    function maxRateAtTarget() external returns (int256) envfree;
    function wexpUpperValue() external returns (int256) envfree;
}

rule wExpTotal(int256 x) {
    wExpExt@withrevert(x);

    assert !lastReverted;
}

rule wExpBounded(int256 x) {
    int256 result = wExpExt(x);

    assert result >= 0;
    assert result <= wexpUpperValue();
}

rule boundInRange(int256 x, int256 low, int256 high) {
    require low <= high;

    int256 result = boundExt@withrevert(x, low, high);
    bool reverted = lastReverted;

    assert !reverted;
    assert reverted || (result >= low && result <= high);
}

rule wDivDownBounded(uint256 x, uint256 y) {
    // Market.totalBorrowAssets and Market.totalSupplyAssets are uint128 (lib/morpho-blue/src/interfaces/IMorpho.sol).
    require x <= max_uint128 && y <= max_uint128;
    // AdaptiveCurveIrm.sol:79 only evaluates wDivDown when totalSupplyAssets > 0.
    require y > 0;
    // morpho-blue proves invariant borrowLessThanSupply (certora/specs/ConsistentState.spec).
    require x <= y;

    uint256 result = wDivDownExt@withrevert(x, y);
    bool reverted = lastReverted;

    assert !reverted;
    assert reverted || result <= 10^18;
}

rule newRateAtTargetInRange(int256 startRateAtTarget, int256 linearAdaptation) {
    // INV_RAT, proved as invariant rateAtTargetInRange in NeverReverts.spec.
    require startRateAtTarget == 0 ||
        (startRateAtTarget >= minRateAtTarget() && startRateAtTarget <= maxRateAtTarget());

    int256 result = newRateAtTargetExt@withrevert(startRateAtTarget, linearAdaptation);
    bool reverted = lastReverted;

    assert !reverted;
    assert reverted || (result >= minRateAtTarget() && result <= maxRateAtTarget());
}

rule curveTotal(int256 rateAtTargetArg, int256 err) {
    // INV_RAT gives 0 <= avgRateAtTarget <= MAX_RATE_AT_TARGET, proved as invariant rateAtTargetInRange.
    require rateAtTargetArg >= 0 && rateAtTargetArg <= maxRateAtTarget();
    // Implied by totalBorrowAssets <= totalSupplyAssets: utilization <= WAD, hence |err| <= WAD.
    require err >= -(10^18) && err <= 10^18;

    int256 result = curveExt@withrevert(rateAtTargetArg, err);
    bool reverted = lastReverted;

    assert !reverted;
    assert reverted || result >= 0;
}
