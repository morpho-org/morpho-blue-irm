// SPDX-License-Identifier: UNLICENCED
methods {
    function libWExp(int256) external returns uint256 envfree;
    function checkedWExp(int256) external returns uint256 envfree;
}

rule wExpRevertConditions(int256 x) {
    libWExp@withrevert(x);
    bool libReverted = lastReverted;

    checkedWExp@withrevert(x);
    bool checkedReverted = lastReverted;

    assert libReverted <=> checkedReverted;
}
