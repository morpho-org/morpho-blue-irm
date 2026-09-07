// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AdaptiveCurveIrm} from "../../src/adaptive-curve-irm/AdaptiveCurveIrm.sol";
import {AdaptiveCurveIrmLib} from "../../src/adaptive-curve-irm/libraries/periphery/AdaptiveCurveIrmLib.sol";
import {ExpLib} from "../../src/adaptive-curve-irm/libraries/ExpLib.sol";
import {UtilsLib} from "../../src/adaptive-curve-irm/libraries/UtilsLib.sol";
import {ConstantsLib} from "../../src/adaptive-curve-irm/libraries/ConstantsLib.sol";
import {WAD_INT} from "../../src/adaptive-curve-irm/libraries/MathLib.sol";
import {MathLib as MorphoMathLib} from "../../lib/morpho-blue/src/libraries/MathLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Id, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";

contract AdaptiveCurveIrmHarness is AdaptiveCurveIrm {
    using MarketParamsLib for MarketParams;

    constructor(address morpho) AdaptiveCurveIrm(morpho) {}

    function toId(MarketParams memory marketParams) external pure returns (Id) {
        return marketParams.id();
    }

    function wExpExt(int256 x) external pure returns (int256) {
        return ExpLib.wExp(x);
    }

    function boundExt(int256 x, int256 low, int256 high) external pure returns (int256) {
        return UtilsLib.bound(x, low, high);
    }

    function curveExt(int256 _rateAtTarget, int256 err) external pure returns (int256) {
        return AdaptiveCurveIrmLib._curve(_rateAtTarget, err);
    }

    function newRateAtTargetExt(int256 startRateAtTarget, int256 linearAdaptation) external pure returns (int256) {
        return AdaptiveCurveIrmLib._newRateAtTarget(startRateAtTarget, linearAdaptation);
    }

    function wDivDownExt(uint256 x, uint256 y) external pure returns (uint256) {
        return MorphoMathLib.wDivDown(x, y);
    }

    function wadInt() external pure returns (int256) {
        return WAD_INT;
    }

    function curveSteepness() external pure returns (int256) {
        return ConstantsLib.CURVE_STEEPNESS;
    }

    function adjustmentSpeed() external pure returns (int256) {
        return ConstantsLib.ADJUSTMENT_SPEED;
    }

    function targetUtilization() external pure returns (int256) {
        return ConstantsLib.TARGET_UTILIZATION;
    }

    function initialRateAtTarget() external pure returns (int256) {
        return ConstantsLib.INITIAL_RATE_AT_TARGET;
    }

    function minRateAtTarget() external pure returns (int256) {
        return ConstantsLib.MIN_RATE_AT_TARGET;
    }

    function maxRateAtTarget() external pure returns (int256) {
        return ConstantsLib.MAX_RATE_AT_TARGET;
    }

    function lnWeiInt() external pure returns (int256) {
        return ExpLib.LN_WEI_INT;
    }

    function wexpUpperBound() external pure returns (int256) {
        return ExpLib.WEXP_UPPER_BOUND;
    }

    function wexpUpperValue() external pure returns (int256) {
        return ExpLib.WEXP_UPPER_VALUE;
    }
}
