// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MathLib} from "../src/libraries/MathLib.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {wadExp} from "../lib/solmate/src/utils/SignedWadMath.sol";

import {AdaptativeCurveIrm} from "../src/SpeedJumpIrm.sol";
import "../lib/forge-std/src/Test.sol";

contract MathLibTest is Test {
    using MathLib for uint128;
    using MathLib for uint256;

    /// @dev ln(1e-9) truncated at 2 decimal places.
    int256 internal constant LN_GWEI_INT = -20.72 ether;

    function testWExp(int256 x) public {
        // Bounded to have sub-1% relative error.
        x = bound(x, LN_GWEI_INT, MathLib.WEXP_UPPER_BOUND);

        assertApproxEqRel(MathLib.wExp(x), uint256(wadExp(x)), 0.01 ether);
    }

    function testWExpSmall(int256 x) public {
        x = bound(x, MathLib.LN_WEI_INT, LN_GWEI_INT);

        assertApproxEqAbs(MathLib.wExp(x), 0, 1e10);
    }

    function testWExpTooSmall(int256 x) public {
        x = bound(x, type(int256).min, MathLib.LN_WEI_INT);

        assertEq(MathLib.wExp(x), 0);
    }

    function testWExpTooLarge(int256 x) public {
        x = bound(x, MathLib.WEXP_UPPER_BOUND, type(int256).max);

        assertEq(MathLib.wExp(x), MathLib.WEXP_UPPER_VALUE);
    }
}
