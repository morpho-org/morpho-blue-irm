// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../src/libraries/UtilsLib.sol";

import "../lib/forge-std/src/Test.sol";

contract UtilsTest is Test {
    using UtilsLib for uint256;

    function testBound(uint256 x, uint256 low, uint256 high) public {
        if (x <= high) {
            if (x >= low) assertEq(x.bound(low, high), x);
            else assertEq(x.bound(low, high), low);
        } else {
            if (low <= high) assertEq(x.bound(low, high), high);
            else assertEq(x.bound(low, high), low);
        }
    }
}
