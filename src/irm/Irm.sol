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
    uint256 private immutable jumpFactor;
    // Scaled by WAD.
    uint256 private immutable speedFactor;
    // Scaled by WAD.
    uint256 private immutable targetUtilization;

    // Storage.

    // Scaled by WAD.
    mapping(Id => uint256) public prevBorrowRate;
    // Scaled by WAD.
    mapping(Id => uint256) public prevUtilization;

    // Constructor.

    constructor(address morpho, uint256 newJumpFactor, uint256 newSpeedFactor, uint256 newTargetUtilization) {
        MORPHO = morpho;
        jumpFactor = newJumpFactor;
        speedFactor = newSpeedFactor;
        targetUtilization = newTargetUtilization;
    }

    // Borrow rates.

    function borrowRateView(MarketParams memory marketParams, Market memory market) public view returns (uint256) {
        (,,, uint256 averageBorrowRate) = _borrowRate(marketParams, market);
        return averageBorrowRate;
    }

    function borrowRate(MarketParams memory marketParams, Market memory market) external returns (uint256) {
        require(msg.sender == MORPHO, NOT_MORPHO);

        (Id id, uint256 utilization, uint256 newBorrowRate, uint256 averageBorrowRate) =
            _borrowRate(marketParams, market);

        if (prevBorrowRate[id] == 0) {
            // First time.
            prevBorrowRate[id] = WAD;
            prevUtilization[id] = utilization;
            return WAD;
        } else {
            prevUtilization[id] = utilization;
            prevBorrowRate[id] = newBorrowRate;
            return averageBorrowRate;
        }
    }

    /// @dev Returns `utilization`, `newBorrowRate` and `averageBorrowRate`.
    function _borrowRate(MarketParams memory marketParams, Market memory market)
        private
        view
        returns (Id, uint256, uint256, uint256)
    {
        Id id = marketParams.id();
        uint256 elapsed = market.lastUpdate - block.timestamp;

        // `utilization` is scaled by WAD.
        uint256 utilization = market.totalBorrowAssets.wDivDown(market.totalSupplyAssets);
        // `err` is between -1 and 1, scaled by WAD.
        int256 err = int256(utilization) - int256(targetUtilization);
        // `prevErr` is between -1 and 1, scaled by WAD.
        int256 prevErr = int256(prevUtilization[id]) - int256(targetUtilization);
        // `errDelta` is between -2 and 2, scaled by WAD.
        int256 errDelta = err - prevErr;

        // Instantaneous.
        uint256 jumpMultiplier = wPow(jumpFactor, errDelta);
        // Per second, to compound continuously.
        uint256 speedMultiplier = speedFactor.wMulDown(uint256(int256(WAD) + err));

        // newBorrowRate = prevBorrowRate * jumpMultiplier * exp(speedMultiplier * t1-t0)
        uint256 newBorrowRate = prevBorrowRate[id].wMulDown(jumpMultiplier).wMulDown(wExp(speedMultiplier * elapsed));

        // averageBorrowRate = ∫ exp(prevBorrowRate * speedMultiplier * t) dt between 0 and elapsed.
        uint256 averageBorrowRate = (wExp(prevBorrowRate[id].wMulDown(speedMultiplier) * elapsed) - WAD) / speedMultiplier;

        return (id, utilization, newBorrowRate, averageBorrowRate);
    }
}
