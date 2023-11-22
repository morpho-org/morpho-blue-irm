// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MathLib} from "../../src/libraries/MathLib.sol";
import {ErrorsLib} from "../../src/libraries/ErrorsLib.sol";
import {wadExp} from "../../lib/solmate/src/utils/SignedWadMath.sol";

import {AdaptiveCurveIrm} from "../../src/SpeedJumpIrm.sol";
import "../../lib/forge-std/src/Test.sol";

contract MathLibTest is Test {
    using MathLib for uint128;
    using MathLib for uint256;

    /// @dev ln(1e-9) truncated at 2 decimal places.
    int256 internal constant LN_GWEI_INT = -20.72 ether;

    function testWExp(int256 x) public {
        // Bounded to have sub-1% relative error.
        x = bound(x, LN_GWEI_INT, MathLib.WEXP_UPPER_BOUND);

        assertApproxEqRel(MathLib.wExp(x), wadExp(x), 0.01 ether);
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

    function testWExpDoesNotLeadToOverflow() public {
        assertGt(MathLib.WEXP_UPPER_VALUE * 1e18, 0);
    }

    function testWExpContinuousUpperBound() public {
        assertApproxEqRel(MathLib.wExp(MathLib.WEXP_UPPER_BOUND - 1), MathLib.WEXP_UPPER_VALUE, 1e-10 ether);
    }

    function testWExpPositive(int256 x) public {
        x = bound(x, 0, type(int256).max);

        assertGe(MathLib.wExp(x), 1e18);
    }

    function testWExpNegative(int256 x) public {
        x = bound(x, type(int256).min, 0);

        assertLe(MathLib.wExp(x), 1e18);
    }
}
