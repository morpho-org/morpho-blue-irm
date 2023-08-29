// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {WAD, MathLib} from "morpho-blue/libraries/MathLib.sol";

int256 constant WAD_INT = int256(WAD);

library IrmMathLib {
    using MathLib for uint128;
    using MathLib for uint256;
    using {wDivDown} for int256;
    using {wMulDown} for int256;

    /// @dev 3rd-order Taylor polynomial of A^x (exponential function with base A), for x around 0.
    /// @dev Warning: `ln(A)` must be passed as an argument and not `A` directly.
    function wExp(int256 lnA, int256 x) internal pure returns (uint256) {
        int256 firstTerm = WAD_INT;
        int256 secondTerm = lnA.wMulDown(x);
        int256 thirdTerm = secondTerm.wMulDown(lnA).wMulDown(x) / 2;
        int256 fourthTerm = thirdTerm.wMulDown(lnA).wMulDown(x) / 3;
        int256 res = firstTerm + secondTerm + thirdTerm + fourthTerm;
        // Safe "unchecked" cast.
        return uint256(res);
    }

    /// @dev 16th-order Taylor polynomial of e^x, for x around 0.
    function wExp(int256 x) internal pure returns (uint256) {
        // `N` should be even otherwise the result can be negative.
        int256 N = 16;
        int256 res = WAD_INT;
        int256 factorial = 1;
        int256 pow = WAD_INT;
        for (int256 k = 1; k <= N; k++) {
            factorial *= k;
            pow = pow.wMulDown(x);
            res += pow / factorial;
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
