// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IIrm} from "../lib/morpho-blue/src/interfaces/IIrm.sol";

import {MathLib} from "./libraries/MathLib.sol";
import {UtilsLib} from "./libraries/UtilsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Id, MarketParams, Market} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {WAD, MathLib as MorphoMathLib} from "../lib/morpho-blue/src/libraries/MathLib.sol";

import "forge-std/console.sol";

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
    event BorrowRateUpdate(Id indexed id, uint256 avgBorrowRate, uint256 baseRate);

    /* CONSTANTS */

    /// @notice Maximum rate per second (scaled by WAD) (1B% APR).
    uint256 public constant MAX_RATE = uint256(1e7 ether) / 365 days;
    /// @notice Mininimum rate per second (scaled by WAD) (0.1% APR).
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
    uint256 public immutable INITIAL_BASE_RATE;

    /* STORAGE */

    /// @notice Base rate of markets.
    mapping(Id => uint256) public baseRate;

    /* CONSTRUCTOR */

    /// @notice Constructor.
    /// @param morpho The address of Morpho.
    /// @param lnJumpFactor The log of the jump factor (scaled by WAD).
    /// @param speedFactor The speed factor (scaled by WAD).
    /// @param targetUtilization The target utilization (scaled by WAD). Should be strictly between 0 and 1.
    /// @param initialBaseRate The initial rate (scaled by WAD).
    constructor(
        address morpho,
        uint256 lnJumpFactor,
        uint256 speedFactor,
        uint256 targetUtilization,
        uint256 initialBaseRate
    ) {
        require(lnJumpFactor <= uint256(type(int256).max), ErrorsLib.INPUT_TOO_LARGE);
        require(speedFactor <= uint256(type(int256).max), ErrorsLib.INPUT_TOO_LARGE);
        require(targetUtilization < WAD, ErrorsLib.INPUT_TOO_LARGE);
        require(targetUtilization > 0, ErrorsLib.ZERO_INPUT);

        MORPHO = morpho;
        LN_JUMP_FACTOR = lnJumpFactor;
        SPEED_FACTOR = speedFactor;
        TARGET_UTILIZATION = targetUtilization;
        INITIAL_BASE_RATE = initialBaseRate;
    }

    /* BORROW RATES */

    /// @inheritdoc IIrm
    function borrowRateView(MarketParams memory marketParams, Market memory market) external view returns (uint256) {
        (uint256 avgBorrowRate,) = _borrowRate(marketParams.id(), market);
        return avgBorrowRate;
    }

    /// @inheritdoc IIrm
    function borrowRate(MarketParams memory marketParams, Market memory market) external returns (uint256) {
        require(msg.sender == MORPHO, ErrorsLib.NOT_MORPHO);

        Id id = marketParams.id();

        (uint256 avgBorrowRate, uint256 newBaseRate) = _borrowRate(id, market);

        baseRate[id] = newBaseRate;

        emit BorrowRateUpdate(id, avgBorrowRate, newBaseRate);

        return avgBorrowRate;
    }

    /// @dev Returns err, newBorrowRate and avgBorrowRate.
    function _borrowRate(Id id, Market memory market) private view returns (uint256, uint256) {
        uint256 utilization =
            market.totalSupplyAssets > 0 ? market.totalBorrowAssets.wDivDown(market.totalSupplyAssets) : 0;

        uint256 errNormFactor = utilization > TARGET_UTILIZATION ? WAD - TARGET_UTILIZATION : TARGET_UTILIZATION;
        // Safe "unchecked" int256 casts because utilization <= WAD, TARGET_UTILIZATION < WAD and errNormFactor <= WAD.
        int256 err = (int256(utilization) - int256(TARGET_UTILIZATION)).wDivDown(int256(errNormFactor));

        // Safe "unchecked" cast because SPEED_FACTOR <= type(int256).max.
        console.log("baseRateIRM", baseRate[id]);
        int256 speed = int256(SPEED_FACTOR).wMulDown(err);
        console.log("speedIRM", uint256(speed));
        uint256 elapsed = (baseRate[id] > 0) ? block.timestamp - market.lastUpdate : 0;
        console.log("elapsedIRM", elapsed);
        // Safe "unchecked" cast because elapsed <= block.timestamp.
        int256 linearVariation = speed * int256(elapsed);
        uint256 variationMultiplier = MathLib.wExp(linearVariation);
        console.log("variationMultiplierIRM", variationMultiplier);
        uint256 newBaseRate = (baseRate[id] > 0) ? baseRate[id].wMulDown(variationMultiplier) : INITIAL_BASE_RATE;
        uint256 newBorrowRate = newBaseRate.wMulDown(MathLib.wExp(err.wMulDown(int256(LN_JUMP_FACTOR))));
        console.log("newBorrowRateIRM", newBorrowRate);

        // Then we compute the average rate over the period (this is what Morpho needs to accrue the interest).
        // avgBorrowRate = 1 / elapsed * ∫ borrowRateAfterJump * exp(speed * t) dt between 0 and elapsed
        //               = borrowRateAfterJump * (exp(linearVariation) - 1) / linearVariation
        //               = (newBorrowRate - borrowRateAfterJump) / linearVariation
        // And avgBorrowRate ~ borrowRateAfterJump for linearVariation around zero.
        uint256 avgBorrowRate;
        if (linearVariation == 0 || baseRate[id] == 0) {
            avgBorrowRate = newBorrowRate;
        } else {
            // Safe "unchecked" cast to uint256 because linearVariation < 0 <=> newBorrowRate <= borrowRateAfterJump.
            avgBorrowRate = uint256(
                (
                    int256(newBorrowRate)
                        - int256(baseRate[id].wMulDown(MathLib.wExp(err.wMulDown(int256(LN_JUMP_FACTOR)))))
                ).wDivDown(linearVariation)
            );
        }

        console.log("avgBorrowRateIRM", avgBorrowRate);

        // We bound both newBorrowRate and avgBorrowRate between MIN_RATE and MAX_RATE.
        return (avgBorrowRate, newBaseRate);
    }
}
