// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ACIBalancesLib} from "../../src/adaptive-curve-irm/libraries/periphery/ACIBalancesLib.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {Id, Market, MarketParams, IMorpho} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";

contract BalancesLibWrapper {
    using MarketParamsLib for MarketParams;

    function adaptiveCurveIrmExpectedMarketBalances(IMorpho morpho, Id id, address adaptiveCurveIrm)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return ACIBalancesLib.expectedMarketBalances(address(morpho), Id.unwrap(id), adaptiveCurveIrm);
    }

    function morphoExpectedMarketBalances(IMorpho morpho, MarketParams memory marketParams)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return MorphoBalancesLib.expectedMarketBalances(morpho, marketParams);
    }

    function toId(MarketParams memory marketParams) external pure returns (Id) {
        return marketParams.id();
    }
}
