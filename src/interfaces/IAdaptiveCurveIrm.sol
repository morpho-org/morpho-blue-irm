// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IIrm} from "../../lib/morpho-blue/src/interfaces/IIrm.sol";
import {Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IAdaptiveCurveIrm is IIrm {
    function MORPHO() external view returns (address);

    function CURVE_STEEPNESS() external view returns (int256);
    function ADJUSTMENT_SPEED() external view returns (int256);
    function TARGET_UTILIZATION() external view returns (int256);
    function INITIAL_RATE_AT_TARGET() external view returns (int256);

    function rateAtTarget(Id id) external view returns (int256);
}
