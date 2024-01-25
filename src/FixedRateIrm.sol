// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IIrm} from "../lib/morpho-blue/src/interfaces/IIrm.sol";
import {IFixedRateIrm} from "./interfaces/IFixedRateIrm.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Id, MarketParams, Market} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";

/// @title FixedRateIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.org
contract FixedRateIrm is IFixedRateIrm {
    using MarketParamsLib for MarketParams;

    /* EVENTS */

    /// @notice Emitted when a borrow rate is set.
    event SetBorrowRate(Id indexed id, uint256 newBorrowRate);

    /* STORAGE */

    /// @notice Borrow rates.
    mapping(Id => uint256) public _borrowRate;

    /* SETTER */

    /// @inheritdoc IFixedRateIrm
    function setBorrowRate(Id id, uint256 newBorrowRate) external {
        require(_borrowRate[id] == 0, ErrorsLib.RATE_ALREADY_SET);
        require(newBorrowRate != 0, ErrorsLib.RATE_ZERO);

        _borrowRate[id] = newBorrowRate;

        emit SetBorrowRate(id, newBorrowRate);
    }

    /* BORROW RATES */

    /// @inheritdoc IIrm
    function borrowRateView(MarketParams memory marketParams, Market memory) external view returns (uint256) {
        return _borrowRate[marketParams.id()];
    }

    /// @inheritdoc IIrm
    function borrowRate(MarketParams memory marketParams, Market memory) external view returns (uint256) {
        return _borrowRate[marketParams.id()];
    }
}
