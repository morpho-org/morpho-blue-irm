// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "solmate/utils/SignedWadMath.sol";
import "../../src/irm/libraries/MathLib.sol";
import "../../src/irm/libraries/ErrorsLib.sol";

contract MathLibTest is Test {
    using MathLib for uint128;
    using MathLib for uint256;

    function testWExp(int256 x) public {
        // Assume x < 256 * -ln(2) ~ -177.
        vm.assume(x > -176 ether);
        // Assume x < ln(2**256) ~ 177.
        vm.assume(x < 176 ether);
        if (x >= 0) assertGe(MathLib.wExp(x), WAD + uint256(x));
        if (x < 0) assertLe(MathLib.wExp(x), WAD);
    }

    function testWExpRef(int256 x) public {
        vm.assume(x > -176 ether);
        vm.assume(x < 135305999368893231589);
        assertApproxEqRel(int256(MathLib.wExp(x)), wadExp(x), 0.03 ether);
    }

    function testWExpRevertTooSmall(int256 x) public {
        vm.assume(x <= -178 ether);
        assertEq(MathLib.wExp(x), 0);
    }

    function testWExpRevertTooLarge(int256 x) public {
        vm.assume(x >= 178 ether);
        vm.expectRevert(bytes(ErrorsLib.WEXP_OVERFLOW));
        MathLib.wExp(x);
    }
}
