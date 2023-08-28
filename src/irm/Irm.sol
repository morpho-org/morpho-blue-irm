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

int256 constant WAD_INT = int256(WAD);

/// @dev Third-order Taylor polynomial of A^x (exponential function with base A), for x around 0.
/// @dev Warning: `ln(A)` must be passed as an argument and not `A` directly.
function wExp(int256 lnA, int256 x) pure returns (uint256) {
    int256 firstTerm = WAD_INT;
    int256 secondTerm = lnA.wMulDown(x);
    int256 thirdTerm = secondTerm.wMulDown(lnA).wMulDown(x) / 2;
    int256 fourthTerm = thirdTerm.wMulDown(lnA).wMulDown(x) / 3;
    int256 res = firstTerm + secondTerm + thirdTerm + fourthTerm;
    // Safe "unchecked" cast.
    return uint256(res);
}

/// @dev Third-order Taylor polynomial of e^x, for x around 0.
function wExp(int256 x) pure returns (uint256) {
    // `N` should be even otherwise the result can be negative.
    int256 N = 16;
    int256 res = WAD_INT;
    int256 factorial = 1;
    int256 pow = WAD_INT;
    for (int256 k = 1; k <= N; k++) {
        factorial *= k;
        pow = pow * x / WAD_INT;
        res += pow / factorial;
    }
    // Safe "unchecked" cast.
    return uint256(res);
}

function wMulDown(int256 a, int256 b) pure returns (int256) {
    return a * b / WAD_INT;
}

function wDivDown(int256 a, int256 b) pure returns (int256) {
    return a * WAD_INT / b;
}

contract Irm is IIrm {
    /* CONSTANTS */

    // Address of Morpho.
    address public immutable MORPHO;
    // Scaled by WAD.
    uint256 public immutable LN_JUMP_FACTOR;
    // Scaled by WAD.
    uint256 public immutable SPEED_FACTOR;
    // Scaled by WAD.
    uint256 public immutable TARGET_UTILIZATION;

    /* STORAGE */

    // Scaled by WAD.
    mapping(Id => uint256) public prevBorrowRate;
    // Scaled by WAD.
    mapping(Id => uint256) public prevUtilization;

    /* CONSTRUCTOR */

    constructor(address newMorpho, uint256 newLnJumpFactor, uint256 newSpeedFactor, uint256 newTargetUtilization) {
        MORPHO = newMorpho;
        LN_JUMP_FACTOR = newLnJumpFactor;
        SPEED_FACTOR = newSpeedFactor;
        TARGET_UTILIZATION = newTargetUtilization;
    }

    /* BORROW RATES */

    function borrowRateView(MarketParams memory marketParams, Market memory market) public view returns (uint256) {
        (,, uint256 avgBorrowRate) = _borrowRate(marketParams.id(), market);
        return avgBorrowRate;
    }

    function borrowRate(MarketParams memory marketParams, Market memory market) external returns (uint256) {
        require(msg.sender == MORPHO, "not Morpho");

        Id id = marketParams.id();

        (uint256 utilization, uint256 newBorrowRate, uint256 avgBorrowRate) = _borrowRate(id, market);

        prevUtilization[id] = utilization;
        prevBorrowRate[id] = newBorrowRate;
        return avgBorrowRate;
    }

    /// @dev Returns `utilization`, `newBorrowRate` and `avgBorrowRate`.
    function _borrowRate(Id id, Market memory market) private view returns (uint256, uint256, uint256) {
        uint256 utilization = market.totalBorrowAssets.wDivDown(market.totalSupplyAssets);

        uint256 prevBorrowRateCached = prevBorrowRate[id];
        if (prevBorrowRateCached == 0) return (utilization, WAD, WAD);

        // `err` is between -TARGET_UTILIZATION and 1-TARGET_UTILIZATION, scaled by WAD.
        // Safe "unchecked" casts.
        int256 err = int256(utilization) - int256(TARGET_UTILIZATION);
        // errDelta = err - prevErr = utilization - target - (prevUtilization - target) = utilization - prevUtilization.
        // `errDelta` is between -1 and 1, scaled by WAD.
        // Safe "unchecked" casts.
        int256 errDelta = int256(utilization) - int256(prevUtilization[id]);

        // Safe "unchecked" cast.
        uint256 jumpMultiplier = wExp(int256(LN_JUMP_FACTOR), errDelta);
        // Safe "unchecked" cast.
        int256 speed = int256(SPEED_FACTOR).wMulDown(err);
        uint256 elapsed = market.lastUpdate - block.timestamp;
        uint256 compoundedRelativeVariation = wExp(speed * int256(elapsed));

        // newBorrowRate = prevBorrowRate * jumpMultiplier * exp(speedMultiplier * t1-t0)
        uint256 newBorrowRate = prevBorrowRateCached.wMulDown(jumpMultiplier).wMulDown(compoundedRelativeVariation);
        // avgBorrowRate = 1 / elapsed * ∫ prevBorrowRate * exp(speed * t) dt between 0 and elapsed.
        uint256 avgBorrowRate = uint256(
            (int256(prevBorrowRateCached.wMulDown(compoundedRelativeVariation)) - WAD_INT).wDivDown(
                speed * int256(elapsed)
            )
        );

        return (utilization, newBorrowRate, avgBorrowRate);
    }
}
