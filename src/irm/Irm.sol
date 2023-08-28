// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IrmMath} from "./libraries/IrmMath.sol";
import {IIrm} from "../../lib/morpho-blue/src/interfaces/IIrm.sol";
import {UtilsLib} from "../../lib/morpho-blue/src/libraries/UtilsLib.sol";
import {WAD, MathLib} from "../../lib/morpho-blue/src/libraries/MathLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Id, MarketParams, Market} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";

struct MarketIrm {
    // Scaled by WAD.
    uint128 prevBorrowRate;
    // Scaled by WAD.
    uint128 prevUtilization;
}

contract Irm is IIrm {
    using IrmMath for int256;
    using MathLib for uint128;
    using MathLib for uint256;
    using IrmMath for uint256;
    using UtilsLib for uint256;
    using MarketParamsLib for MarketParams;

    /* CONSTANTS */

    // Address of Morpho.
    address public immutable MORPHO;
    // Scaled by WAD.
    uint256 public immutable LN_JUMP_FACTOR;
    // Scaled by WAD.
    uint256 public immutable SPEED_FACTOR;
    // Scaled by WAD.
    uint256 public immutable TARGET_UTILIZATION;
    // Per second, scaled by WAD.
    uint256 public immutable INITIAL_RATE;

    /* STORAGE */

    mapping(Id => MarketIrm) public marketIrm;

    /* CONSTRUCTOR */

    constructor(
        address newMorpho,
        uint256 newLnJumpFactor,
        uint256 newSpeedFactor,
        uint256 newTargetUtilization,
        uint256 newInitialRate
    ) {
        require(newLnJumpFactor <= uint256(type(int256).max), "too big");
        require(newSpeedFactor <= uint256(type(int256).max), "too big");
        require(newTargetUtilization <= uint256(type(int256).max), "too big");

        MORPHO = newMorpho;
        LN_JUMP_FACTOR = newLnJumpFactor;
        SPEED_FACTOR = newSpeedFactor;
        TARGET_UTILIZATION = newTargetUtilization;
        INITIAL_RATE = newInitialRate;
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

        marketIrm[id].prevUtilization = utilization.toUint128();
        marketIrm[id].prevBorrowRate = newBorrowRate.toUint128();
        return avgBorrowRate;
    }

    /// @dev Returns `utilization`, `newBorrowRate` and `avgBorrowRate`.
    function _borrowRate(Id id, Market memory market) private view returns (uint256, uint256, uint256) {
        uint256 utilization = market.totalBorrowAssets.wDivDown(market.totalSupplyAssets);

        uint256 prevBorrowRateCached = marketIrm[id].prevBorrowRate;
        if (prevBorrowRateCached == 0) return (utilization, INITIAL_RATE, INITIAL_RATE);

        // `err` is between -TARGET_UTILIZATION and 1-TARGET_UTILIZATION, scaled by WAD.
        // Safe "unchecked" casts.
        int256 err = int256(utilization) - int256(TARGET_UTILIZATION);
        // errDelta = err - prevErr = utilization - target - (prevUtilization - target) = utilization - prevUtilization.
        // `errDelta` is between -1 and 1, scaled by WAD.
        // Safe "unchecked" casts.
        int256 errDelta = int256(utilization) - int128(marketIrm[id].prevUtilization);

        // Safe "unchecked" cast.
        uint256 jumpMultiplier = IrmMath.wExp(int256(LN_JUMP_FACTOR), errDelta);
        // Safe "unchecked" cast.
        int256 speed = int256(SPEED_FACTOR).wMulDown(err);
        // `elapsed` is never zero, because Morpho skips the interest accrual in this case.
        uint256 elapsed = market.lastUpdate - block.timestamp;
        uint256 compoundedRelativeVariation = IrmMath.wExp(speed * int256(elapsed));

        // newBorrowRate = prevBorrowRate * jumpMultiplier * exp(speedMultiplier * t1-t0)
        uint256 newBorrowRate = prevBorrowRateCached.wMulDown(jumpMultiplier).wMulDown(compoundedRelativeVariation);
        // avgBorrowRate = 1 / elapsed * ∫ prevBorrowRate * exp(speed * t) dt between 0 and elapsed.
        uint256 avgBorrowRate = uint256(
            (int256(prevBorrowRateCached.wMulDown(compoundedRelativeVariation)) - IrmMath.WAD_INT).wDivDown(
                speed * int256(elapsed)
            )
        );

        return (utilization, newBorrowRate, newBorrowRate);
    }
}
