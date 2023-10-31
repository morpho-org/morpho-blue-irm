// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IIrm} from "../lib/morpho-blue/src/interfaces/IIrm.sol";

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {MathLib, WAD_INT} from "./libraries/MathLib.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Id, MarketParams, Market} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {WAD, MathLib as MorphoMathLib} from "../lib/morpho-blue/src/libraries/MathLib.sol";

/// @title AdaptativeCurveIRM
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
contract AdaptativeCurveIRM is IIrm {
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

    /// @notice Maximum base rate per second (scaled by WAD) (1B% APR).
    uint256 public constant MAX_BASE_RATE = uint256(1e7 ether) / 365 days;
    /// @notice Mininimum base rate per second (scaled by WAD) (0.1% APR).
    uint256 public constant MIN_BASE_RATE = uint256(0.001 ether) / 365 days;
    /// @notice Address of Morpho.
    address public immutable MORPHO;
    /// @notice Curve steepness (scaled by WAD).
    /// @dev Verified to be greater than 1 at construction.
    uint256 public immutable CURVE_STEEPNESS;
    /// @notice Adjustment speed (scaled by WAD).
    /// @dev The speed is per second, so the rate moves at a speed of ADJUSTMENT_SPEED * err each second (while being
    /// continuously compounded). A typical value for the ADJUSTMENT_SPEED would be 10 ethers / 365 days.
    uint256 public immutable ADJUSTMENT_SPEED;
    /// @notice Target utilization (scaled by WAD).
    /// @dev Verified to be strictly between 0 and 1 at construction.
    uint256 public immutable TARGET_UTILIZATION;
    /// @notice Initial rate (scaled by WAD).
    uint256 public immutable INITIAL_BASE_RATE;

    /* STORAGE */

    /// @notice Base rate of markets.
    mapping(Id => uint256) public baseRate;

    /* CONSTRUCTOR */

    /// @notice Constructor.
    /// @param morpho The address of Morpho.
    /// @param curveSteepness The curve steepness (scaled by WAD).
    /// @param adjustmentSpeed The adjustment speed (scaled by WAD).
    /// @param targetUtilization The target utilization (scaled by WAD).
    /// @param initialBaseRate The initial base rate (scaled by WAD).
    constructor(
        address morpho,
        uint256 curveSteepness,
        uint256 adjustmentSpeed,
        uint256 targetUtilization,
        uint256 initialBaseRate
    ) {
        require(curveSteepness <= uint256(type(int256).max), ErrorsLib.INPUT_TOO_LARGE);
        require(curveSteepness >= WAD, ErrorsLib.INPUT_TOO_SMALL);
        require(adjustmentSpeed <= uint256(type(int256).max), ErrorsLib.INPUT_TOO_LARGE);
        require(targetUtilization < WAD, ErrorsLib.INPUT_TOO_LARGE);
        require(targetUtilization > 0, ErrorsLib.ZERO_INPUT);

        MORPHO = morpho;
        CURVE_STEEPNESS = curveSteepness;
        ADJUSTMENT_SPEED = adjustmentSpeed;
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

        int256 linearVariation;
        {
            // Safe "unchecked" cast because ADJUSTMENT_SPEED <= type(int256).max.
            int256 speed = int256(ADJUSTMENT_SPEED).wMulDown(err);
            uint256 elapsed = (baseRate[id] > 0) ? block.timestamp - market.lastUpdate : 0;
            // Safe "unchecked" cast because elapsed <= block.timestamp.
            linearVariation = speed * int256(elapsed);
        }

        uint256 newBaseRate =
            (baseRate[id] > 0) ? baseRate[id].wMulDown(MathLib.wExp(linearVariation)) : INITIAL_BASE_RATE;
        uint256 newBorrowRate = _curve(newBaseRate, err);

        // Then we compute the average rate over the period (this is what Morpho needs to accrue the interest).
        // avgBorrowRate = 1 / elapsed * ∫ borrowRateStartOfThePeriod * exp(speed * t) dt between 0 and elapsed
        //               = borrowRateStartOfThePeriod * (exp(linearVariation) - 1) / linearVariation
        //               = (newBorrowRate - borrowRateStartOfThePeriod) / linearVariation
        // And avgBorrowRate ~ borrowRateStartOfThePeriod ~ newBorrowRate for linearVariation around zero.
        // Also, when it is the first interaction (baseRate == 0).
        uint256 avgBorrowRate;
        if (linearVariation == 0 || baseRate[id] == 0) {
            avgBorrowRate = newBorrowRate;
        } else {
            // Safe "unchecked" cast to uint256 because linearVariation < 0 <=> newBorrowRate <=
            // borrowRateStartOfThePeriod.
            avgBorrowRate =
                uint256((int256(newBorrowRate) - int256(_curve(baseRate[id], err))).wDivDown(linearVariation));
        }

        // We bound both newBorrowRate and avgBorrowRate between MIN_RATE and MAX_RATE.
        return (avgBorrowRate, newBaseRate.bound(MIN_BASE_RATE, MAX_BASE_RATE));
    }

    function _curve(uint256 _baseRate, int256 err) internal view returns (uint256) {
        // Safe "unchecked" cast because err >= -1 (in WAD).
        if (err < 0) {
            return uint256((WAD_INT - WAD_INT.wDivDown(int256(CURVE_STEEPNESS))).wMulDown(err) + WAD_INT).wMulDown(
                _baseRate
            );
        }
        return uint256((int256(CURVE_STEEPNESS) - WAD_INT).wMulDown(err) + WAD_INT).wMulDown(_baseRate);
    }
}
