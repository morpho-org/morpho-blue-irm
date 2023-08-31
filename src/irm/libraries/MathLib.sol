// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {WAD, MathLib as MorphoMathLib} from "morpho-blue/libraries/MathLib.sol";

int256 constant WAD_INT = int256(WAD);

library MathLib {
    using MathLib for uint128;
    using MathLib for uint256;
    using {wDivDown} for int256;
    using {wMulDown} for int256;

    /// @dev 3rd-order Taylor polynomial of e^x, for x around 0.
    function wExp3(int256 x) internal pure returns (uint256) {
        int256 firstTerm = WAD_INT;
        int256 secondTerm = x;
        int256 thirdTerm = secondTerm.wMulDown(x) / 2;
        int256 fourthTerm = thirdTerm.wMulDown(x) / 3;
        int256 res = firstTerm + secondTerm + thirdTerm + fourthTerm;
        // Safe "unchecked" cast.
        return uint256(res);
    }

    /// @dev 12th-order Taylor polynomial of e^x, for x around 0.
    /// @dev The approximation error is less than 11% between -3 and 3. Above 3, the function still returns the same
    /// Taylor polynomial, and below -3 the function returns 0.05.
    function wExp12(int256 x) internal pure returns (uint256) {
        // The approximation error increases quickly below x = -3, so we hardcode the result.
        if (x < -3 * WAD_INT) return 0.05 ether;

        // `N` should be even otherwise the result can be negative.
        int256 N = 12;
        int256 res = WAD_INT;
        int256 monomial = WAD_INT;
        for (int256 k = 1; k <= N; k++) {
            monomial = monomial.wMulDown(x) / k;
            res += monomial;
        }
        // Safe "unchecked" cast.
        return uint256(res);
    }

    function wMulDown(int256 a, int256 b) internal pure returns (int256) {
        return a * b / WAD_INT;
    }

    function wDivDown(int256 a, int256 b) internal pure returns (int256) {
        return a * WAD_INT / b;
    }
}
