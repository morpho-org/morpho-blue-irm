// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IIrm} from "morpho-blue/interfaces/IIrm.sol";

import {MathLib} from "./libraries/MathLib.sol";
import {UtilsLib} from "./libraries/UtilsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {MarketParamsLib} from "morpho-blue/libraries/MarketParamsLib.sol";
import {Id, MarketParams, Market} from "morpho-blue/interfaces/IMorpho.sol";
import {WAD, MathLib as MorphoMathLib} from "morpho-blue/libraries/MathLib.sol";

struct MarketIrm {
    // Previous final borrow rate. Scaled by WAD.
    uint128 prevBorrowRate;
    // Previous error. Scaled by WAD.
    int128 prevErr;
}

/// @title SpeedJumpIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Interest rate model.
contract SpeedJumpIrm is IIrm {
    using MathLib for int256;
    using MathLib for uint256;
    using UtilsLib for uint256;
    using MorphoMathLib for uint128;
    using MorphoMathLib for uint256;
    using MarketParamsLib for MarketParams;

    /* EVENTS */

    /// @notice Emitted when a borrow rate is updated.
    event BorrowRateUpdate(Id indexed id, int128 err, uint128 newBorrowRate, uint256 avgBorrowRate);

    /* CONSTANTS */

    /// @notice Max rate (1B% APR) (per second) (scaled by WAD).
    uint256 public constant MAX_RATE = uint256(1e7 ether) / 365 days;
    /// @notice Min rate (0.1% APR) (per second) (scaled by WAD).
    uint256 public constant MIN_RATE = uint256(0.001 ether) / 365 days;
    /// @notice Address of Morpho.
    address public immutable MORPHO;
    /// @notice Ln of the jump factor (scaled by WAD).
    uint256 public immutable LN_JUMP_FACTOR;
    /// @notice Speed factor (scaled by WAD).
    /// @dev The speed is per second, so the rate moves at a speed of SPEED_FACTOR * err each second (while being
    /// continuously compounded). A typical value for the SPEED_FACTOR would be 10 ethers / 365 days.
    uint256 public immutable SPEED_FACTOR;
    /// @notice Target utilization (scaled by WAD).
    uint256 public immutable TARGET_UTILIZATION;
    /// @notice Initial rate (scaled by WAD).
    uint128 public immutable INITIAL_RATE;

    /* STORAGE */

    /// @notice IRM storage for each market.
    mapping(Id => MarketIrm) public marketIrm;

    /* CONSTRUCTOR */

    /// @notice Constructor.
    /// @param morpho The address of Morpho.
    /// @param lnJumpFactor The log of the jump factor (scaled by WAD).
    /// @param speedFactor The speed factor (scaled by WAD).
    /// @param targetUtilization The target utilization (scaled by WAD). Should be strictly between 0 and 1.
    /// @param initialRate The initial rate (scaled by WAD).
    constructor(
        address morpho,
        uint256 lnJumpFactor,
        uint256 speedFactor,
        uint256 targetUtilization,
        uint128 initialRate
    ) {
        require(lnJumpFactor <= uint256(type(int256).max), ErrorsLib.INPUT_TOO_LARGE);
        require(speedFactor <= uint256(type(int256).max), ErrorsLib.INPUT_TOO_LARGE);
        require(targetUtilization < WAD, ErrorsLib.INPUT_TOO_LARGE);
        require(targetUtilization > 0, ErrorsLib.ZERO_INPUT);

        MORPHO = morpho;
        LN_JUMP_FACTOR = lnJumpFactor;
        SPEED_FACTOR = speedFactor;
        TARGET_UTILIZATION = targetUtilization;
        INITIAL_RATE = initialRate;
    }

    /* BORROW RATES */

    /// @inheritdoc IIrm
    function borrowRateView(MarketParams memory marketParams, Market memory market) external view returns (uint256) {
        (,, uint256 avgBorrowRate) = _borrowRate(marketParams.id(), market);
        return avgBorrowRate;
    }

    /// @inheritdoc IIrm
    function borrowRate(MarketParams memory marketParams, Market memory market) external returns (uint256) {
        require(msg.sender == MORPHO, ErrorsLib.NOT_MORPHO);

        Id id = marketParams.id();

        (int128 err, uint128 newBorrowRate, uint256 avgBorrowRate) = _borrowRate(id, market);

        marketIrm[id].prevErr = err;
        marketIrm[id].prevBorrowRate = newBorrowRate;

        emit BorrowRateUpdate(id, err, newBorrowRate, avgBorrowRate);

        return avgBorrowRate;
    }

    /// @dev Returns err, newBorrowRate and avgBorrowRate.
    function _borrowRate(Id id, Market memory market) private view returns (int128, uint128, uint128) {
        uint256 utilization =
            market.totalSupplyAssets > 0 ? market.totalBorrowAssets.wDivDown(market.totalSupplyAssets) : 0;

        uint256 errNormFactor = utilization > TARGET_UTILIZATION ? WAD - TARGET_UTILIZATION : TARGET_UTILIZATION;
        // Safe "unchecked" int128 cast because |err| <= WAD.
        // Safe "unchecked" int256 casts because utilization <= WAD, TARGET_UTILIZATION < WAD and errNormFactor <= WAD.
        int128 err = int128((int256(utilization) - int256(TARGET_UTILIZATION)).wDivDown(int256(errNormFactor)));

        if (marketIrm[id].prevBorrowRate == 0) return (err, INITIAL_RATE, INITIAL_RATE);

        // errDelta = err - prevErr.
        // errDelta is between -1 and 1, scaled by WAD.
        int256 errDelta = err - marketIrm[id].prevErr;

        // Safe "unchecked" cast because LN_JUMP_FACTOR <= type(int256).max.
        uint256 jumpMultiplier = MathLib.wExp(errDelta.wMulDown(int256(LN_JUMP_FACTOR)));
        // Safe "unchecked" cast because SPEED_FACTOR <= type(int256).max.
        int256 speed = int256(SPEED_FACTOR).wMulDown(err);
        uint256 elapsed = block.timestamp - market.lastUpdate;
        // Safe "unchecked" cast because elapsed <= block.timestamp.
        int256 linearVariation = speed * int256(elapsed);
        uint256 variationMultiplier = MathLib.wExp(linearVariation);

        // newBorrowRate = prevBorrowRate * jumpMultiplier * variationMultiplier.
        uint256 borrowRateAfterJump = marketIrm[id].prevBorrowRate.wMulDown(jumpMultiplier);
        uint256 newBorrowRate = borrowRateAfterJump.wMulDown(variationMultiplier);

        // Then we compute the average rate over the period (this is what Morpho needs to accrue the interest).
        // avgBorrowRate = 1 / elapsed * ∫ borrowRateAfterJump * exp(speed * t) dt between 0 and elapsed
        //               = borrowRateAfterJump * (exp(linearVariation) - 1) / linearVariation
        //               = (newBorrowRate - borrowRateAfterJump) / linearVariation
        // And avgBorrowRate ~ borrowRateAfterJump for linearVariation around zero.
        uint256 avgBorrowRate;
        if (linearVariation == 0) avgBorrowRate = borrowRateAfterJump;
        // Safe "unchecked" cast to uint256 because linearVariation < 0 <=> newBorrowRate <= borrowRateAfterJump.
        else avgBorrowRate = uint256((int256(newBorrowRate) - int256(borrowRateAfterJump)).wDivDown(linearVariation));

        // We bound both newBorrowRate and avgBorrowRate between MIN_RATE and MAX_RATE.
        return (err, uint128(newBorrowRate.bound(MIN_RATE, MAX_RATE)), uint128(avgBorrowRate.bound(MIN_RATE, MAX_RATE)));
    }
}
