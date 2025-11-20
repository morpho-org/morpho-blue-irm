// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AdaptiveCurveIrmBorrowRateView2Lib} from "../../src/adaptive-curve-irm/libraries/external/AdaptiveCurveIrmBorrowRateView2Lib.sol";
import {Id, Market, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";

contract BorrowRateView2Wrapper {
    using MarketParamsLib for MarketParams;

    function borrowRateView2(Id id, Market memory market, address adaptiveCurveIrm) external view returns (uint256) {
        return AdaptiveCurveIrmBorrowRateView2Lib.borrowRateView2(id, market, adaptiveCurveIrm);
    }

    function toId(MarketParams memory marketParams) external pure returns (Id) {
        return marketParams.id();
    }
}