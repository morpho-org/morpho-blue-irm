// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ConstantsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
library ConstantsLib {
    /// @notice Curve steepness (scaled by WAD).
    int256 public constant CURVE_STEEPNESS = 4 ether;

    /// @notice Adjustment speed per second (scaled by WAD).
    int256 public constant ADJUSTMENT_SPEED = int256(50 ether) / 365 days;

    /// @notice Target utilization (scaled by WAD).
    int256 public constant TARGET_UTILIZATION = 0.9 ether;

    /// @notice Initial rate at target per second (scaled by WAD).
    int256 public constant INITIAL_RATE_AT_TARGET = int256(0.04 ether) / 365 days;

    /// @notice Mininimum rate at target per second (scaled by WAD) (0.1% APR).
    int256 public constant MIN_RATE_AT_TARGET = int256(0.001 ether) / 365 days;

    /// @notice Maximum rate at target per second (scaled by WAD) (1B% APR).
    int256 public constant MAX_RATE_AT_TARGET = int256(0.01e9 ether) / 365 days;
}
