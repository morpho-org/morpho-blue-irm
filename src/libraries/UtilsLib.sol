// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title UtilsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing helpers.
library UtilsLib {
    /// @dev Bounds `x` between `low` and `high`.
    /// @dev Assumes that `low` <= `high`. If it is not the case it returns `low`.
    function bound(uint256 x, uint256 low, uint256 high) internal pure returns (uint256 z) {
        assembly {
            // z = min(x, high).
            z := xor(x, mul(xor(x, high), lt(high, x)))
            // z = max(z, low).
            z := xor(z, mul(xor(z, low), gt(low, z)))
        }
    }
}
