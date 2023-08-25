// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IIrm} from "../../lib/morpho-blue/src/interfaces/IIrm.sol";
import {Id, MarketParams, Market} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";

import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {WAD, MathLib} from "../../lib/morpho-blue/src/libraries/MathLib.sol";

using MathLib for uint128;
using MathLib for uint256;
using {wMulDown} for uint256;
using MarketParamsLib for MarketParams;

function wPow(uint256 a, int256 x) pure returns (uint256) {
    uint256 lnA = wLn(a);
    // Always positive.
    return uint256(1 + lnA.wMulDown(x) + wSquare(lnA).wMulDown(wSquare(x)) / 2 + wCube(lnA).wMulDown(wCube(x)) / 6);
}

function wLn(uint256 x) pure returns (uint256) {
    return (x - WAD) - wSquare(x - WAD) / 2 + wCube(x - WAD) / 3;
}

function wMulDown(uint256 a, int256 b) pure returns (int256) {
    return int256(a) * b / int256(WAD);
}

function wExp(uint256 x) pure returns (uint256) {
    return WAD + x + wSquare(x) / 2 + wCube(x) / 6;
}

function wSquare(uint256 x) pure returns (uint256) {
    return x * x / WAD;
}

function wSquare(int256 x) pure returns (int256) {
    return x * x / int256(WAD);
}

function wCube(uint256 x) pure returns (uint256) {
    return wSquare(x) * x / WAD;
}

function wCube(int256 x) pure returns (int256) {
    return wSquare(x) * x / int256(WAD);
}

contract Irm is IIrm {
    // Immutables.

    string private constant NOT_MORPHO = "not Morpho";
    address private immutable MORPHO;
    // Scaled by WAD.
    uint256 private immutable JUMP_FACTOR;
    // Scaled by WAD.
    uint256 private immutable SPEED_FACTOR;
    // Scaled by WAD. Typed signed int but the value is positive.
    int256 private immutable TARGET_UTILIZATION;

    // Storage.

    // Scaled by WAD.
    mapping(Id => uint256) public prevBorrowRate;
    // Scaled by WAD. Typed signed int but the value is positive.
    mapping(Id => int256) public prevUtilization;

    // Constructor.

    constructor(address newMorpho, uint256 newJumpFactor, uint256 newSpeedFactor, uint256 newTargetUtilization) {
        MORPHO = newMorpho;
        JUMP_FACTOR = newJumpFactor;
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

        if (prevBorrowRate[id] == 0) {
            // First time.
            prevBorrowRate[id] = WAD;
            prevUtilization[id] = utilization;
            return WAD;
        } else {
            prevUtilization[id] = utilization;
            prevBorrowRate[id] = newBorrowRate;
            return avgBorrowRate;
        }
    }

    /// @dev Returns `utilization`, `newBorrowRate` and `avgBorrowRate`.
    function _borrowRate(Id id, Market memory market) private view returns (int256, uint256, uint256) {
        // `utilization` is scaled by WAD. Typed signed int but the value is positive.
        int256 utilization = int256(market.totalBorrowAssets.wDivDown(market.totalSupplyAssets));
        // `err` is between -1 and 1, scaled by WAD.
        int256 err = utilization - TARGET_UTILIZATION;
        // `prevErr` is between -1 and 1, scaled by WAD.
        int256 prevErr = prevUtilization[id] - TARGET_UTILIZATION;
        // `errDelta` is between -2 and 2, scaled by WAD.
        int256 errDelta = err - prevErr;

        // Instantaneous jump.
        uint256 jumpMultiplier = wPow(JUMP_FACTOR, errDelta);
        // Per second, to compound continuously.
        uint256 speedMultiplier = SPEED_FACTOR.wMulDown(uint256(int256(WAD) + err));
        // Time since last update.
        uint256 elapsed = market.lastUpdate - block.timestamp;

        // newBorrowRate = prevBorrowRate * jumpMultiplier * exp(speedMultiplier * t1-t0)
        uint256 newBorrowRate = prevBorrowRate[id].wMulDown(jumpMultiplier).wMulDown(wExp(speedMultiplier * elapsed));
        // avgBorrowRate = ∫ exp(prevBorrowRate * speedMultiplier * t) dt between 0 and elapsed.
        uint256 avgBorrowRate = (wExp(prevBorrowRate[id].wMulDown(speedMultiplier) * elapsed) - WAD) / speedMultiplier;

        return (utilization, newBorrowRate, avgBorrowRate);
    }
}
