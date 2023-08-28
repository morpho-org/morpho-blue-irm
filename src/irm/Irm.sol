// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IIrm} from "../../lib/morpho-blue/src/interfaces/IIrm.sol";
import {Id, MarketParams, Market} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";

import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {WAD, MathLib} from "../../lib/morpho-blue/src/libraries/MathLib.sol";

using MathLib for uint128;
using MathLib for uint256;
using {wDivDown} for int256;
using {wMulDown} for int256;
using MarketParamsLib for MarketParams;

/// @dev Returns an approximation of a^x.
/// @dev Warning ln(a) must be passed as argument and not a directly.
function wFloatPow(int256 lnA, int256 x) pure returns (uint256) {
    // Always positive.
    int256 firstTerm = int(WAD);
    int256 secondTerm = lnA.wMulDown(x);
    int256 thirdTerm = secondTerm.wMulDown(lnA).wMulDown(x) / 2;
    int256 fourthTerm = thirdTerm.wMulDown(lnA).wMulDown(x) / 3;
    int256 res = firstTerm + secondTerm + thirdTerm + fourthTerm;
    require(res >= 0, "wPow: res < 0");
    return uint256(res);
}

function wExp(int256 x) pure returns (uint256) {
    // N should be even otherwise the result can get negative.
    int256 N = 16;
    int256 res = int256(WAD);
    int256 factorial = 1;
    int256 pow = int256(WAD);
    // We start at k = 1.
    for (int256 k = 1; k <= N; k++) {
        factorial *= k;
        pow = pow * x / int256(WAD);
        res += pow / factorial;
    }
    return uint256(res);
}

function wMulDown(int256 a, int256 b) pure returns (int256) {
    return a * b / int256(WAD);
}

function wDivDown(int256 a, int256 b) pure returns (int256) {
    return a * int256(WAD) / b;
}

contract Irm is IIrm {
    // Immutables.

    string private constant NOT_MORPHO = "not Morpho";
    address private immutable MORPHO;
    // Scaled by WAD.
    int256 private immutable LN_JUMP_FACTOR;
    // Scaled by WAD.
    int256 private immutable SPEED_FACTOR;
    // Scaled by WAD. Typed signed int but the value is positive.
    int256 private immutable TARGET_UTILIZATION;

    // Storage.

    // Scaled by WAD.
    mapping(Id => uint256) public prevBorrowRate;
    // Scaled by WAD. Typed signed int but the value is positive.
    mapping(Id => int256) public prevUtilization;

    // Constructor.

    constructor(address newMorpho, int256 newLnJumpFactor, int256 newSpeedFactor, uint256 newTargetUtilization) {
        MORPHO = newMorpho;
        LN_JUMP_FACTOR = newLnJumpFactor;
        SPEED_FACTOR = newSpeedFactor;
        TARGET_UTILIZATION = int256(newTargetUtilization);
    }

    // Borrow rates.

    function borrowRateView(MarketParams memory marketParams, Market memory market) public view returns (uint256) {
        (,, uint256 avgBorrowRate) = _borrowRate(marketParams.id(), market);
        return avgBorrowRate;
    }

    function borrowRate(MarketParams memory marketParams, Market memory market) external returns (uint256) {
        require(msg.sender == MORPHO, NOT_MORPHO);

        Id id = marketParams.id();

        (int256 utilization, uint256 newBorrowRate, uint256 avgBorrowRate) = _borrowRate(id, market);

        prevUtilization[id] = utilization;
        prevBorrowRate[id] = newBorrowRate;
        return avgBorrowRate;
    }

    /// @dev Returns `utilization`, `newBorrowRate` and `avgBorrowRate`.
    function _borrowRate(Id id, Market memory market) private view returns (int256, uint256, uint256) {
        // `utilization` is scaled by WAD. Typed signed int but the value is positive.
        int256 utilization = int256(market.totalBorrowAssets.wDivDown(market.totalSupplyAssets));

        uint256 prevBorrowRateCached = prevBorrowRate[id];
        if (prevBorrowRateCached == 0) return (utilization, WAD, WAD);

        // `err` is between -TARGET_UTILIZATION and 1-TARGET_UTILIZATION, scaled by WAD.
        int256 err = utilization - TARGET_UTILIZATION;
        // `prevErr` is between -TARGET_UTILIZATION and 1-TARGET_UTILIZATION, scaled by WAD.
        int256 prevErr = prevUtilization[id] - TARGET_UTILIZATION;
        // `errDelta` is between -1 and 1, scaled by WAD.
        int256 errDelta = err - prevErr;

        // Instantaneous jump.
        uint256 jumpMultiplier = wFloatPow(LN_JUMP_FACTOR, errDelta);
        // Per second, to compound continuously.
        int256 speed = SPEED_FACTOR.wMulDown(err);
        // Time since last update (positive).
        int256 elapsed = int256(market.lastUpdate - block.timestamp);

        // newBorrowRate = prevBorrowRate * jumpMultiplier * exp(speedMultiplier * t1-t0)
        uint256 newBorrowRate = uint256(prevBorrowRateCached.wMulDown(jumpMultiplier).wMulDown(wExp(speed * elapsed)));
        // avgBorrowRate = 1 / elapsed * ∫ prevBorrowRate * exp(speed * t) dt between 0 and elapsed.
        uint256 avgBorrowRate = uint256(
            (int256(prevBorrowRateCached.wMulDown(wExp(speed * elapsed))) - int256(WAD)).wDivDown(speed * elapsed)
        );

        return (utilization, newBorrowRate, avgBorrowRate);
    }
}
