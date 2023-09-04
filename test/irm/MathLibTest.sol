// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "solmate/utils/SignedWadMath.sol";
import "../../src/irm/libraries/MathLib.sol";
import "../../src/irm/libraries/ErrorsLib.sol";

contract MathLibTest is Test {
    using MathLib for uint128;
    using MathLib for uint256;

    int256 private constant LN2_INT = 0.693147180559945309 ether;

    function testWExp(int256 x) public {
        x = bound(x, -27 ether, 94 ether);
        assertApproxEqRel(MathLib.wExp(x), uint256(wadExp(x)), 0.01 ether);
    }

    function testWExpSmall(int256 x) public {
        x = bound(x, type(int256).min + LN2_INT / 2, -178 ether);
        assertEq(MathLib.wExp(x), 0);
    }

    function testWExpTooSmall(int256 x) public {
        x = bound(x, type(int256).min, type(int256).min + LN2_INT / 2 - 1);
        vm.expectRevert(bytes(ErrorsLib.WEXP_UNDERFLOW));
        assertEq(MathLib.wExp(x), 0);
    }

    function testWExpTooLarge(int256 x) public {
        vm.assume(x >= 178 ether);
        vm.expectRevert(bytes(ErrorsLib.WEXP_OVERFLOW));
        MathLib.wExp(x);
    }
}
