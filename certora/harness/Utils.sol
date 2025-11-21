// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Id, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";

contract Utils {
    using MarketParamsLib for MarketParams;

    function toId(MarketParams memory marketParams) external pure returns (Id) {
        return marketParams.id();
    }
}
