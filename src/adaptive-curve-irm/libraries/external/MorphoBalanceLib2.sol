// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Id, Market, IMorpho} from "../../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IAdaptiveCurveIrm} from "../../interfaces/IAdaptiveCurveIrm.sol";

import {ExpLib} from "../../libraries/ExpLib.sol";
import {UtilsLib} from "../../libraries/UtilsLib.sol";
import {ConstantsLib} from "../../libraries/ConstantsLib.sol";
import {MathLib, WAD_INT as WAD} from "../../libraries/MathLib.sol";
import {SharesMathLib} from "lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {Id, Market} from "../../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MathLib as MorphoMathLib} from "lib/morpho-blue/src/libraries/MathLib.sol";
import {UtilsLib as MorphoUtilsLib} from "lib/morpho-blue/src/libraries/UtilsLib.sol";
import {MathLib as MorphoMathLib} from "../../../../lib/morpho-blue/src/libraries/MathLib.sol";

library MorphoBalancesLib2 {
    using MathLib for int256;
    using UtilsLib for int256;
    using MorphoMathLib for uint256;
    using MorphoMathLib for uint128;
    using MorphoUtilsLib for uint256;
    using SharesMathLib for uint256;

    function expectedMarketBalances2(IMorpho morpho, Id id, address adaptiveCurveIrm)
        internal
        view
        returns (uint256, uint256, uint256, uint256)
    {
        Market memory market = morpho.market(id);

        uint256 elapsed = block.timestamp - market.lastUpdate;

        if (elapsed != 0 && market.totalBorrowAssets != 0) {
            uint256 borrowRate = _borrowRateView2(id, market, adaptiveCurveIrm);
            uint256 interest = market.totalBorrowAssets.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            market.totalBorrowAssets += interest.toUint128();
            market.totalSupplyAssets += interest.toUint128();

            if (market.fee != 0) {
                uint256 feeAmount = interest.wMulDown(market.fee);
                uint256 feeShares =
                    feeAmount.toSharesDown(market.totalSupplyAssets - feeAmount, market.totalSupplyShares);
                market.totalSupplyShares += feeShares.toUint128();
            }
        }

        return (market.totalSupplyAssets, market.totalSupplyShares, market.totalBorrowAssets, market.totalBorrowShares);
    }

    function _borrowRateView2(Id id, Market memory market, address irm) internal view returns (uint256) {
        int256 utilization =
            int256(market.totalSupplyAssets > 0 ? market.totalBorrowAssets.wDivDown(market.totalSupplyAssets) : 0);

        int256 errNormFactor = utilization > ConstantsLib.TARGET_UTILIZATION
            ? WAD - ConstantsLib.TARGET_UTILIZATION
            : ConstantsLib.TARGET_UTILIZATION;
        int256 err = (utilization - ConstantsLib.TARGET_UTILIZATION).wDivToZero(errNormFactor);

        int256 startRateAtTarget = IAdaptiveCurveIrm(irm).rateAtTarget(id);

        int256 avgRateAtTarget;

        if (startRateAtTarget == 0) {
            avgRateAtTarget = ConstantsLib.INITIAL_RATE_AT_TARGET;
        } else {
            int256 speed = ConstantsLib.ADJUSTMENT_SPEED.wMulToZero(err);
            int256 elapsed = int256(block.timestamp - market.lastUpdate);
            int256 linearAdaptation = speed * elapsed;

            if (linearAdaptation == 0) {
                avgRateAtTarget = startRateAtTarget;
            } else {
                int256 endRateAtTarget = _newRateAtTarget(startRateAtTarget, linearAdaptation);
                int256 midRateAtTarget = _newRateAtTarget(startRateAtTarget, linearAdaptation / 2);
                avgRateAtTarget = (startRateAtTarget + endRateAtTarget + 2 * midRateAtTarget) / 4;
            }
        }

        return (uint256(_curve(avgRateAtTarget, err)));
    }

    function _curve(int256 _rateAtTarget, int256 err) private pure returns (int256) {
        int256 coeff = err < 0 ? WAD - WAD.wDivToZero(ConstantsLib.CURVE_STEEPNESS) : ConstantsLib.CURVE_STEEPNESS - WAD;
        return (coeff.wMulToZero(err) + WAD).wMulToZero(int256(_rateAtTarget));
    }

    function _newRateAtTarget(int256 startRateAtTarget, int256 linearAdaptation) private pure returns (int256) {
        return startRateAtTarget.wMulToZero(ExpLib.wExp(linearAdaptation))
            .bound(ConstantsLib.MIN_RATE_AT_TARGET, ConstantsLib.MAX_RATE_AT_TARGET);
    }
}
