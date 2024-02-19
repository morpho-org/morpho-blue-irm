// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IIrm} from "../../lib/morpho-blue/src/interfaces/IIrm.sol";
import {IFixedRateIrm} from "./interfaces/IFixedRateIrm.sol";

import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Id, MarketParams, Market} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";

/* ERRORS */

/// @dev Thrown when the rate is not already set for this market.
string constant RATE_NOT_SET = "rate not set";
/// @dev Thrown when the rate is already set for this market.
string constant RATE_SET = "rate set";
/// @dev Thrown when trying to set the rate at zero.
string constant RATE_ZERO = "rate zero";

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
    mapping(Id => uint256) public borrowRateStored;

    /* SETTER */

    /// @notice Sets the borrow rate for a market.
    /// @dev A rate can be set by anybody, but only once.
    /// @dev `borrowRate` reverts on rate not set, so the rate needs to be set before the market creation.
    function setBorrowRate(Id id, uint256 newBorrowRate) external {
        require(borrowRateStored[id] == 0, RATE_SET);
        require(newBorrowRate != 0, RATE_ZERO);

        borrowRateStored[id] = newBorrowRate;

        emit SetBorrowRate(id, newBorrowRate);
    }

    /* BORROW RATES */

    /// @inheritdoc IIrm
    function borrowRateView(MarketParams memory marketParams, Market memory) external view returns (uint256) {
        uint256 borrowRateCached = borrowRateStored[marketParams.id()];
        require(borrowRateCached != 0, RATE_NOT_SET);
        return borrowRateCached;
    }

    /// @inheritdoc IIrm
    /// @dev Reverts on not set rate, so the rate has to be set before the market creation.
    function borrowRate(MarketParams memory marketParams, Market memory) external view returns (uint256) {
        uint256 borrowRateCached = borrowRateStored[marketParams.id()];
        require(borrowRateCached != 0, RATE_NOT_SET);
        return borrowRateCached;
    }
}
