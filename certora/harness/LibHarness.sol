// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "../munged/libraries/MathLib.sol";

contract LibHarness {
    using {MathLib.wMulDown} for int256;

    int256 public constant LN2_INT = 0.693147180559945309 ether;

    function libWExp(int256 x) public pure returns (uint256) {
        return MathLib.wExp(x);
    }

    function checkedWExp(int256 x) public pure returns (uint256) {
        require(x <= 177.44567822334599921 ether, ErrorsLib.WEXP_OVERFLOW);
        require(x >= type(int256).min + LN2_INT / 2, ErrorsLib.WEXP_UNDERFLOW);

        int256 roundingAdjustment = (x < 0) ? -(LN2_INT / 2) : (LN2_INT / 2);
        int256 q = (x + roundingAdjustment) / LN2_INT;
        int256 r = x - q * LN2_INT;

        uint256 expR = uint256(WAD_INT + r + r.wMulDown(r) / 2);

        if (q >= 0) return expR << uint256(q);
        else return expR >> uint256(-q);
    }
}
