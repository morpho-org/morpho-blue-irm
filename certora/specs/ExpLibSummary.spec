// SPDX-License-Identifier: MIT

methods {
    function wExpExt(int256) external returns (int256) envfree;
    function boundExt(int256, int256, int256) external returns (int256) envfree;
    function wDivDownExt(uint256, uint256) external returns (uint256) envfree;
    function wexpUpperValue() external returns (int256) envfree;
}

rule wExpBounded(int256 x) {
    int256 result = wExpExt@withrevert(x);
    bool reverted = lastReverted;

    assert !reverted;
    assert reverted || (result >= 0 && result <= wexpUpperValue());
}

rule boundInRange(int256 x, int256 low, int256 high) {
    // AdaptiveCurveIrm.sol:148 passes MIN_RATE_AT_TARGET, MAX_RATE_AT_TARGET, and MIN < MAX.
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
    // morpho-blue proves invariant borrowLessThanSupply (lib/morpho-blue/certora/specs/ConsistentState.spec).
    require x <= y;

    uint256 result = wDivDownExt@withrevert(x, y);
    bool reverted = lastReverted;

    assert !reverted;
    assert reverted || result <= 10^18;
}
