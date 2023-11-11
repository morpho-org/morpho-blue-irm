// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library ConstantsLib {
    /// @notice Maximum rate at target per second (scaled by WAD) (1B% APR).
    int256 internal constant MAX_RATE_AT_TARGET = int256(0.01e9 ether) / 365 days;

    /// @notice Mininimum rate at target per second (scaled by WAD) (0.1% APR).
    int256 internal constant MIN_RATE_AT_TARGET = int256(0.001 ether) / 365 days;

    /// @notice Maximum curve steepness allowed (scaled by WAD).
    int256 internal constant MAX_CURVE_STEEPNESS = 100 ether;

    /// @notice Maximum adjustment speed allowed (scaled by WAD).
    int256 internal constant MAX_ADJUSTMENT_SPEED = int256(1_000 ether) / 365 days;
}
