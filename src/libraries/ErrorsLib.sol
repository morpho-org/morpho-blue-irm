// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ErrorsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing error messages.
library ErrorsLib {
    /// @dev Thrown when passing the zero address.
    string internal constant ZERO_ADDRESS = "zero address";

    /// @dev Thrown when the caller is not Morpho.
    string internal constant NOT_MORPHO = "not Morpho";

    /// @dev Thrown when the rate is already set for this market.
    string internal constant RATE_ALREADY_SET = "rate already set";

    /// @dev Thrown when trying to set the rate at zero.
    string internal constant RATE_ZERO = "rate zero";
}
