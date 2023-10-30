// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title ErrorsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library exposing error messages.
library ErrorsLib {
    /// @dev Thrown when the input is too large to fit in the expected type.
    string internal constant INPUT_TOO_LARGE = "input too large";

    /// @dev Thrown when passing the zero input.
    string internal constant ZERO_INPUT = "zero input";

    /// @dev Thrown when wExp overflows.
    string internal constant WEXP_OVERFLOW = "wExp overflow";

    /// @dev Thrown when the caller is not Morpho.
    string internal constant NOT_MORPHO = "not Morpho";
}
