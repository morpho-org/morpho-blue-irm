// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ExpLib} from "../src/libraries/adaptative-curve/ExpLib.sol";
import {wadExp} from "../lib/solmate/src/utils/SignedWadMath.sol";

import "../lib/forge-std/src/Test.sol";

contract ExpLibTest is Test {
    /// @dev ln(1e-9) truncated at 2 decimal places.
    int256 internal constant LN_GWEI_INT = -20.72 ether;

    function testWExp(int256 x) public {
        // Bounded to have sub-1% relative error.
        x = bound(x, LN_GWEI_INT, ExpLib.WEXP_UPPER_BOUND);

        assertApproxEqRel(ExpLib.wExp(x), wadExp(x), 0.01 ether);
    }

    function testWExpSmall(int256 x) public {
        x = bound(x, ExpLib.LN_WEI_INT, LN_GWEI_INT);

        assertApproxEqAbs(ExpLib.wExp(x), 0, 1e10);
    }

    function testWExpTooSmall(int256 x) public {
        x = bound(x, type(int256).min, ExpLib.LN_WEI_INT);

        assertEq(ExpLib.wExp(x), 0);
    }

    function testWExpTooLarge(int256 x) public {
        x = bound(x, ExpLib.WEXP_UPPER_BOUND, type(int256).max);

        assertEq(ExpLib.wExp(x), ExpLib.WEXP_UPPER_VALUE);
    }

    function testWExpDoesNotLeadToOverflow() public {
        assertGt(ExpLib.WEXP_UPPER_VALUE * 1e18, 0);
    }

    function testWExpContinuousUpperBound() public {
        assertApproxEqRel(ExpLib.wExp(ExpLib.WEXP_UPPER_BOUND - 1), ExpLib.WEXP_UPPER_VALUE, 1e-10 ether);
    }

    function testWExpPositive(int256 x) public {
        x = bound(x, 0, type(int256).max);

        assertGe(ExpLib.wExp(x), 1e18);
    }

    function testWExpNegative(int256 x) public {
        x = bound(x, type(int256).min, 0);

        assertLe(ExpLib.wExp(x), 1e18);
    }
}
