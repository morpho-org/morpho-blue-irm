// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/irm/libraries/IrmMathLib.sol";

contract IrmTest is Test {
    using MathLib for uint128;
    using MathLib for uint256;

    uint256 constant INITIAL_RATE = uint256(0.01 ether) / uint256(365 days);
    uint256 constant ln2 = 0.69314718056 ether;

    function testWExpWithBaseA() public {
        assertApproxEqRel(IrmMathLib.wExp(int256(ln2), -1 ether), 0.5 ether, 0.02 ether);
        assertApproxEqRel(IrmMathLib.wExp(int256(ln2), -0.5 ether), 0.70710678118 ether, 0.01 ether);
        assertEq(IrmMathLib.wExp(int256(ln2), 0), 1 ether);
        assertApproxEqRel(IrmMathLib.wExp(int256(ln2), 0.5 ether), 1.41421356237 ether, 0.01 ether);
        assertApproxEqRel(IrmMathLib.wExp(int256(ln2), 1 ether), 2 ether, 0.02 ether);
    }

    function testWExpWithBaseA(int256 x) public view {
        x = bound(x, -1 ether, 1 ether);
        IrmMathLib.wExp(int256(ln2), x);
    }

    function testWExp() public {
        assertApproxEqRel(IrmMathLib.wExp(-4 ether), 0.01831563888 ether, 0.01 ether);
        assertApproxEqRel(IrmMathLib.wExp(-3 ether), 0.04978706836 ether, 0.00001 ether);
        assertApproxEqRel(IrmMathLib.wExp(-2 ether), 0.13533528323 ether, 0.000001 ether);
        assertApproxEqRel(IrmMathLib.wExp(-1 ether), 0.36787944117 ether, 0.00000001 ether);
        assertApproxEqRel(IrmMathLib.wExp(0 ether), 1.0 ether, 0.0 ether);
        assertApproxEqRel(IrmMathLib.wExp(1 ether), 2.71828182846 ether, 0.00000001 ether);
        assertApproxEqRel(IrmMathLib.wExp(2 ether), 7.38905609893 ether, 0.000001 ether);
        assertApproxEqRel(IrmMathLib.wExp(3 ether), 20.0855369232 ether, 0.00001 ether);
        assertApproxEqRel(IrmMathLib.wExp(4 ether), 54.5981500331 ether, 0.001 ether);
        assertApproxEqRel(IrmMathLib.wExp(5 ether), 148.413159103 ether, 0.01 ether);
    }

    function testWExp(int256 x) public {
        x = bound(x, -4 ether, 4 ether);
        assertGe(int256(IrmMathLib.wExp(x)), int256(WAD) + x);
    }
}
