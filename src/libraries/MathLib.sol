// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {WAD} from "../../lib/morpho-blue/src/libraries/MathLib.sol";

int256 constant WAD_INT = int256(WAD);

/// @title MathLib
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library to manage fixed-point arithmetic and approximate the exponential function.
library MathLib {
    using MathLib for uint128;
    using MathLib for uint256;
    using {wDivDown} for int256;

    /// @dev ln(2).
    int256 internal constant LN2_INT = 0.693147180559945309 ether;

    /// @dev Above this limit `wExp` would overflow. Instead, we return an upper value.
    int256 internal constant WEXP_UPPER_BOUND = 135.999582271169154765 ether;

    /// @dev The value of wExp(WEXP_UPPER_BOUND).
    uint256 internal constant WEXP_UPPER_VALUE =
        115792089237316195323137357242501015631897353894317901381819.896896488577433600 ether;

    /// @dev Returns an approximation of exp.
    function wExp(int256 x) internal pure returns (uint256) {
        unchecked {
            // Return an upper value to avoid overflows.
            if (x >= WEXP_UPPER_BOUND) return WEXP_UPPER_VALUE;

            // Return zero if x < -(2**255-1) + (ln(2)/2).
            if (x < type(int256).min + LN2_INT / 2) return 0;

            // Decompose x as x = q * ln(2) + r with q an integer and -ln(2)/2 <= r <= ln(2)/2.
            // q = x / ln(2) rounded half toward zero.
            int256 roundingAdjustment = (x < 0) ? -(LN2_INT / 2) : (LN2_INT / 2);
            // Safe unchecked because x is bounded.
            int256 q = (x + roundingAdjustment) / LN2_INT;
            // Safe unchecked because |q * LN2_INT| <= |x|.
            int256 r = x - q * LN2_INT;

            // Compute e^r with a 2nd-order Taylor polynomial.
            // Safe unchecked because |r| < 1, expR < 2 and the sum is positive.
            uint256 expR = uint256(WAD_INT + r + (r * r) / WAD_INT / 2);

            // Return e^x = 2^q * e^r.
            if (q >= 0) return expR << uint256(q);
            else return expR >> uint256(-q);
        }
    }

    function wMulDown(uint256 a, int256 b) internal pure returns (int256) {
        require(a <= uint256(type(int256).max));
        return int256(a) * b / WAD_INT;
    }

    function wDivDown(int256 a, int256 b) internal pure returns (int256) {
        return a * WAD_INT / b;
    }
}
