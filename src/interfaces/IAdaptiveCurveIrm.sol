// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IIrm} from "../../lib/morpho-blue/src/interfaces/IIrm.sol";
import {Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IAdaptiveCurveIrm is IIrm {
    /// @notice Address of Morpho.
    function MORPHO() external view returns (address);

    /// @notice Curve steepness (scaled by WAD).
    /// @dev Verified to be inside the expected range at construction.
    function CURVE_STEEPNESS() external view returns (int256);

    /// @notice Adjustment speed (scaled by WAD).
    /// @dev The speed is per second, so the rate moves at a speed of ADJUSTMENT_SPEED * err each second (while being
    /// continuously compounded). A typical value for the ADJUSTMENT_SPEED would be 10 ether / 365 days.
    /// @dev Verified to be inside the expected range at construction.
    function ADJUSTMENT_SPEED() external view returns (int256);

    /// @notice Target utilization (scaled by WAD).
    /// @dev Verified to be strictly between 0 and 1 at construction.
    function TARGET_UTILIZATION() external view returns (int256);

    /// @notice Initial rate at target per second (scaled by WAD).
    /// @dev Verified to be between MIN_RATE_AT_TARGET and MAX_RATE_AT_TARGET at contruction.
    function INITIAL_RATE_AT_TARGET() external view returns (int256);

    /// @notice Rate at target utilization.
    /// @dev Tells the height of the curve.
    function rateAtTarget(Id id) external view returns (int256);
}
