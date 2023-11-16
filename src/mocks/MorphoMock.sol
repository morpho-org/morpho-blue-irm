// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Id, MarketParams, MarketParamsLib, ErrorsLib, Morpho} from "../../lib/morpho-blue/src/Morpho.sol";

contract MorphoMock is Morpho {
    using MarketParamsLib for MarketParams;

    constructor(address newOwner) Morpho(newOwner) {}

    function accrueInterest(MarketParams memory marketParams) external {
        Id id = marketParams.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);

        _accrueInterest(marketParams, id);
    }
}
