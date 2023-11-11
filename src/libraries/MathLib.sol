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
    int256 internal constant LN_2_INT = 0.693147180559945309 ether;

    /// @dev ln(1e-18).
    int256 internal constant LN_WEI_INT = -41.446531673892822312 ether;

    /// @dev Above this bound, `wExp` is clipped to avoid overflowing when multiplied with 1 ether.
    /// @dev This upper bound corresponds to: ln(type(uint256).max / 1e36) - ln(2) (scaled by WAD, floored).
    int256 internal constant WEXP_UPPER_BOUND = 93.859467695000409276 ether;

    /// @dev The value of wExp(`WEXP_UPPER_BOUND`).
    uint256 internal constant WEXP_UPPER_VALUE = 57716089161559221271663333261689707872312.488815486643994624 ether;

    /// @dev Returns an approximation of exp.
    function wExp(int256 x) internal pure returns (uint256) {
        unchecked {
            // If x < ln(1e-18) then exp(x) < 1e-18 so it is rounded to zero.
            if (x < LN_WEI_INT) return 0;
            if (x >= WEXP_UPPER_BOUND) return WEXP_UPPER_VALUE;

            // Decompose x as x = q * ln(2) + r with q an integer and -ln(2)/2 <= r <= ln(2)/2.
            // q = x / ln(2) rounded half toward zero.
            int256 roundingAdjustment = (x < 0) ? -(LN_2_INT / 2) : (LN_2_INT / 2);
            // Safe unchecked because x is bounded.
            int256 q = (x + roundingAdjustment) / LN_2_INT;
            // Safe unchecked because |q * ln(2) - x| <= ln(2)/2.
            int256 r = x - q * LN_2_INT;

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
