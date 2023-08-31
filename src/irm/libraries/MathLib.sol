// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {WAD, MathLib as MorphoMathLib} from "morpho-blue/libraries/MathLib.sol";

int256 constant WAD_INT = int256(WAD);

library MathLib {
    using MathLib for uint128;
    using MathLib for uint256;
    using {wDivDown} for int256;
    using {wMulDown} for int256;

    /// @dev 12th-order Taylor polynomial of e^x, for x around 0.
    /// @dev The approximation error is less than 1% between -3 and 3. Above 3, the function returns 20 and below -3 the
    /// function returns 0.05.
    function wExp12(int256 x) internal pure returns (uint256) {
        // The approximation error increases quickly below x = -3, so we hardcode the result.
        if (x < -3 * WAD_INT) return 0.05 ether;
        if (x > 3 * WAD_INT) return 20 ether;

        // `N` should be even otherwise the result can be negative.
        int256 N = 12;
        int256 res = WAD_INT;
        int256 monomial = WAD_INT;
        for (int256 k = 1; k <= N; k++) {
            monomial = monomial.wMulDown(x) / k;
            res += monomial;
        }
        // Safe "unchecked" cast because N is even.
        return uint256(res);
    }

    function wMulDown(int256 a, int256 b) internal pure returns (int256) {
        return a * b / WAD_INT;
    }

    function wDivDown(int256 a, int256 b) internal pure returns (int256) {
        return a * WAD_INT / b;
    }
}
