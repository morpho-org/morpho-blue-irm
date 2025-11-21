// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Id, Market, IMorpho} from "../../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

import {MathLib as MorphoMathLib} from "../../../../lib/morpho-blue/src/libraries/MathLib.sol";
import {UtilsLib as MorphoUtilsLib} from "../../../../lib/morpho-blue/src/libraries/UtilsLib.sol";
import {Id, Market} from "../../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {SharesMathLib} from "../../../../lib/morpho-blue/src/libraries/SharesMathLib.sol";

import {AdaptiveCurveIrmBorrowRateView2Lib} from "./AdaptiveCurveIrmBorrowRateView2Lib.sol";

import {console2} from "../../../../lib/forge-std/src/console2.sol";

library AdaptiveCurveIrmBalancesLib {
    using MorphoMathLib for uint256;
    using MorphoMathLib for uint128;
    using SharesMathLib for uint256;
    using MorphoUtilsLib for uint256;

    function expectedMarketBalances(IMorpho morpho, Id id, address adaptiveCurveIrm)
        internal
        view
        returns (uint256, uint256, uint256, uint256)
    {
        Market memory market = morpho.market(id);

        uint256 elapsed = block.timestamp - market.lastUpdate;

        // Skipped if elapsed == 0 or totalBorrowAssets == 0 because interest would be null.
        if (elapsed != 0 && market.totalBorrowAssets != 0) {
            uint256 borrowRate = AdaptiveCurveIrmBorrowRateView2Lib.borrowRateView2(id, market, adaptiveCurveIrm);
            uint256 interest = market.totalBorrowAssets.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            market.totalBorrowAssets += interest.toUint128();
            market.totalSupplyAssets += interest.toUint128();

            if (market.fee != 0) {
                uint256 feeAmount = interest.wMulDown(market.fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact
                // that total supply is already updated.
                uint256 feeShares =
                    feeAmount.toSharesDown(market.totalSupplyAssets - feeAmount, market.totalSupplyShares);
                market.totalSupplyShares += feeShares.toUint128();
            }
        }

        return (market.totalSupplyAssets, market.totalSupplyShares, market.totalBorrowAssets, market.totalBorrowShares);
    }
}
