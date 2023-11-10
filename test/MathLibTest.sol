// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MathLib} from "../src/libraries/MathLib.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {wadExp} from "../lib/solmate/src/utils/SignedWadMath.sol";

import "../lib/forge-std/src/Test.sol";

contract MathLibTest is Test {
    using MathLib for uint128;
    using MathLib for uint256;

    int256 private constant LN2_INT = 0.693147180559945309 ether;

    function testWExp(int256 x) public {
        // Bound between ln(1e-9) ~ -27 and ln(max / 1e18 / 1e18) ~ 94, to be able to use `assertApproxEqRel`.
        x = bound(x, -27 ether, 94 ether);
        assertApproxEqRel(MathLib.wExp(x), wadExp(x), 0.01 ether);
    }

    function testWExpSmall(int256 x) public {
        // Bound between -2**255 + ln(2)/2 and ln(1e-18).
        x = bound(x, type(int256).min + LN2_INT / 2, -178 ether);
        assertEq(MathLib.wExp(x), 0);
    }

    function testWExpTooSmall(int256 x) public {
        // Bound between -2**255 and -2**255 + ln(2)/2 - 1.
        x = bound(x, type(int256).min, type(int256).min + LN2_INT / 2 - 1);
        assertEq(MathLib.wExp(x), 0);
    }

    function testWExpTooLarge(int256 x) public {
        // Bound between ln(2**256-1) ~ 177 and 2**255-1.
        x = bound(x, 178 ether, type(int256).max);
        vm.expectRevert(bytes(ErrorsLib.WEXP_OVERFLOW));
        MathLib.wExp(x);
    }
}
