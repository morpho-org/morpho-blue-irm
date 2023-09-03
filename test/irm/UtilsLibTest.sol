// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/irm/libraries/UtilsLib.sol";

contract UtilsTest is Test {
    using UtilsLib for uint256;

    function testBound(uint256 x, uint256 low, uint256 high) public {
        uint256 expectedRes = (x > high ? high : x) < low ? low : (x > high ? high : x);
        assertEq(x.bound(low, high), expectedRes);
    }
}
