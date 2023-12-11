// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WAD_INT} from "../MathLib.sol";

/// @title ConstantsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
library ConstantsLib {
    int256 public constant ONE_BPS = 0.0001 ether;

    /// @notice Curve steepness (scaled by WAD).
    int256 public constant CURVE_STEEPNESS = 4 ether;

    /// @notice Adjustment speed per second (scaled by WAD).
    int256 public constant ADJUSTMENT_SPEED = int256(50 ether) / 365 days;

    /// @notice Target utilization (scaled by WAD).
    int256 public constant TARGET_UTILIZATION = 0.9 ether;

    /// @notice Initial rate at target per second (scaled by WAD).
    int256 public constant INITIAL_RATE_AT_TARGET = 4_00 * ONE_BPS / 365 days;

    /// @notice Minimum rate at target per second (scaled by WAD) (min APR is MAX_RATE_AT_TARGET / CURVE_STEEPNESS).
    int256 public constant MIN_RATE_AT_TARGET = 10 * ONE_BPS / 365 days;

    /// @notice Maximum rate at target per second (scaled by WAD) (max APR is MAX_RATE_AT_TARGET * CURVE_STEEPNESS).
    int256 public constant MAX_RATE_AT_TARGET = 200_00 * ONE_BPS / 365 days;
}
