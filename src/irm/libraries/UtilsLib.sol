// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ErrorsLib} from "./ErrorsLib.sol";

library UtilsLib {
    /// @dev Returns `x` safely cast to int128.
    function toInt128(int256 x) internal pure returns (int128) {
        require(x <= type(int128).max, ErrorsLib.MAX_INT128_EXCEEDED);
        return int128(x);
    }
}
