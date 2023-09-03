// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/irm/libraries/MathLib.sol";

contract MathLibTest is Test {
    using MathLib for uint128;
    using MathLib for uint256;

    function testWExp() public {
        assertApproxEqRel(MathLib.wExp(-3 ether), 0.04978706836 ether, 0.01 ether);
        assertApproxEqRel(MathLib.wExp(-2 ether), 0.13533528323 ether, 0.01 ether);
        assertApproxEqRel(MathLib.wExp(-1 ether), 0.36787944117 ether, 0.01 ether);
        assertEq(MathLib.wExp(0 ether), 1.0 ether);
        assertApproxEqRel(MathLib.wExp(1 ether), 2.71828182846 ether, 0.01 ether);
        assertApproxEqRel(MathLib.wExp(2 ether), 7.38905609893 ether, 0.01 ether);
        assertApproxEqRel(MathLib.wExp(3 ether), 20.0855369232 ether, 0.01 ether);
    }

    function testWExp(int256 x) public {
        // Assume x < 256 * -ln(2) ~ -177.
        vm.assume(x > -176 ether);
        // Assume x < ln(2**256) ~ 177.
        vm.assume(x < 176 ether);
        if (x >= 0) assertGe(MathLib.wExp(x), WAD + uint256(x));
        if (x < 0) assertLe(MathLib.wExp(x), WAD);
    }

    function testWExpRef(int256 x) public {
        x = bound(x, -3 ether, 3 ether);
        assertApproxEqRel(MathLib.wExp(x), wExpRef(x), 0.03 ether);
    }
}

function wExpRef(int256 x) pure returns (uint256) {
    // `N` should be even otherwise the result can be negative.
    int256 N = 64;
    int256 res = WAD_INT;
    int256 monomial = WAD_INT;
    for (int256 k = 1; k <= N; k++) {
        monomial = monomial * x / WAD_INT / k;
        res += monomial;
    }
    // Safe "unchecked" cast because `N` is even.
    return uint256(res);
}
