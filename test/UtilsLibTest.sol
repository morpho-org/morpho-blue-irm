// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {UtilsLib} from "@irm/src/libraries/UtilsLib.sol";

import "@irm/lib/forge-std/src/Test.sol";

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
