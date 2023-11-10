// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ErrorsLib} from "./ErrorsLib.sol";
import {WAD} from "../../lib/morpho-blue/src/libraries/MathLib.sol";

int256 constant WAD_INT = int256(WAD);
int256 constant LN2_INT = 0.693147180559945309 ether;

/// @title MathLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library to manage fixed-point arithmetic and approximate the exponential function.
library MathLib {
    using MathLib for uint128;
    using MathLib for uint256;
    using {wDivDown} for int256;

    /// @dev Returns an approximation of exp.
    function wExp(int256 x) internal pure returns (uint256) {
        unchecked {
            // Revert if x > ln(2^256-1) ~ 177.
            require(x <= 177.44567822334599921 ether, ErrorsLib.WEXP_OVERFLOW);
            // Return zero if x < -2**255 + LN2_INT / 2.
            if (x < type(int256).min + LN2_INT / 2) return 0;

            // Decompose x as x = q * ln(2) + r with q an integer and -ln(2)/2 <= r <= ln(2)/2.
            // q = x / ln(2) rounded half toward zero.
            int256 roundingAdjustment = (x < 0) ? -(LN2_INT / 2) : (LN2_INT / 2);
            // Safe unchecked because x is bounded.
            int256 q = (x + roundingAdjustment) / LN2_INT;
            // Safe unchecked because |q * LN2_INT - x| <= LN2_INT/2.
            int256 r = x - q * LN2_INT;

            // Compute e^r with a 2nd-order Taylor polynomial.
            // Safe unchecked because |r| < 1e18, and the sum is positive.
            uint256 expR = uint256(WAD_INT + r + (r * r) / WAD_INT / 2);

            // Return e^x = 2^q * e^r.
            if (q >= 0) return expR << uint256(q);
            else return expR >> uint256(-q);
        }
    }

    function wMulDown(int256 a, int256 b) internal pure returns (int256) {
        return a * b / WAD_INT;
    }

    function wDivDown(int256 a, int256 b) internal pure returns (int256) {
        return a * WAD_INT / b;
    }
}
