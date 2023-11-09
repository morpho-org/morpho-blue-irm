// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IIrm} from "../lib/morpho-blue/src/interfaces/IIrm.sol";

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {MathLib, WAD_INT} from "./libraries/MathLib.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Id, MarketParams, Market} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {WAD, MathLib as MorphoMathLib} from "../lib/morpho-blue/src/libraries/MathLib.sol";

/// @title AdaptativeCurveIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
contract AdaptativeCurveIrm is IIrm {
    using MathLib for int256;
    using MathLib for uint256;
    using UtilsLib for uint256;
    using MorphoMathLib for uint128;
    using MorphoMathLib for uint256;
    using MarketParamsLib for MarketParams;

    /* EVENTS */

    /// @notice Emitted when a borrow rate is updated.
    event BorrowRateUpdate(Id indexed id, uint256 avgBorrowRate, uint256 rateAtTarget);

    /* CONSTANTS */

    /// @notice Maximum rate at target per second (scaled by WAD) (1B% APR).
    uint256 public constant MAX_RATE_AT_TARGET = uint256(1e7 ether) / 365 days;
    /// @notice Mininimum rate at target per second (scaled by WAD) (0.1% APR).
    uint256 public constant MIN_RATE_AT_TARGET = uint256(0.001 ether) / 365 days;
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
    /// @notice Initial rate at target (scaled by WAD).
    uint256 public immutable INITIAL_RATE_AT_TARGET;

    /* STORAGE */

    /// @notice Rate at target utilization.
    /// @dev Tells the height of the curve.
    mapping(Id => uint256) public rateAtTarget;

    /* CONSTRUCTOR */

    /// @notice Constructor.
    /// @param morpho The address of Morpho.
    /// @param curveSteepness The curve steepness (scaled by WAD).
    /// @param adjustmentSpeed The adjustment speed (scaled by WAD).
    /// @param targetUtilization The target utilization (scaled by WAD).
    /// @param initialRateAtTarget The initial rate at target (scaled by WAD).
    constructor(
        address morpho,
        uint256 curveSteepness,
        uint256 adjustmentSpeed,
        uint256 targetUtilization,
        uint256 initialRateAtTarget
    ) {
        require(morpho != address(0), ErrorsLib.ZERO_ADDRESS);
        require(curveSteepness <= uint256(type(int256).max), ErrorsLib.INPUT_TOO_LARGE);
        require(curveSteepness >= WAD, ErrorsLib.INPUT_TOO_SMALL);
        require(adjustmentSpeed <= uint256(type(int256).max), ErrorsLib.INPUT_TOO_LARGE);
        require(targetUtilization < WAD, ErrorsLib.INPUT_TOO_LARGE);
        require(targetUtilization > 0, ErrorsLib.ZERO_INPUT);
        require(initialRateAtTarget >= MIN_RATE_AT_TARGET, ErrorsLib.INPUT_TOO_SMALL);
        require(initialRateAtTarget <= MAX_RATE_AT_TARGET, ErrorsLib.INPUT_TOO_LARGE);

        MORPHO = morpho;
        CURVE_STEEPNESS = curveSteepness;
        ADJUSTMENT_SPEED = adjustmentSpeed;
        TARGET_UTILIZATION = targetUtilization;
        INITIAL_RATE_AT_TARGET = initialRateAtTarget;
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

        (uint256 avgBorrowRate, uint256 newRateAtTarget) = _borrowRate(id, market);

        rateAtTarget[id] = newRateAtTarget;

        emit BorrowRateUpdate(id, avgBorrowRate, newRateAtTarget);

        return avgBorrowRate;
    }

    /// @dev Returns avgBorrowRate and newRateAtTarget.
    /// @dev Assumes that the inputs `marketParams` and `id` match.
    function _borrowRate(Id id, Market memory market) private view returns (uint256, uint256) {
        uint256 utilization =
            market.totalSupplyAssets > 0 ? market.totalBorrowAssets.wDivDown(market.totalSupplyAssets) : 0;

        uint256 errNormFactor = utilization > TARGET_UTILIZATION ? WAD - TARGET_UTILIZATION : TARGET_UTILIZATION;
        // Safe "unchecked" int256 casts because utilization <= WAD, TARGET_UTILIZATION < WAD and errNormFactor <= WAD.
        int256 err = (int256(utilization) - int256(TARGET_UTILIZATION)).wDivDown(int256(errNormFactor));

        uint256 startRateAtTarget = rateAtTarget[id];

        // First interaction.
        if (startRateAtTarget == 0) {
            return (_curve(INITIAL_RATE_AT_TARGET, err), INITIAL_RATE_AT_TARGET);
        } else {
            // Safe "unchecked" cast because ADJUSTMENT_SPEED <= type(int256).max.
            // Note that the speed is assumed constant between two interactions, but in theory it increases because of
            // interests. So the rate will be slightly underestimated.
            int256 speed = ADJUSTMENT_SPEED.wMulDown(err);

            // market.lastUpdate != 0 because it is not the first interaction with this market.
            uint256 elapsed = block.timestamp - market.lastUpdate;
            // Safe "unchecked" cast because elapsed <= block.timestamp.
            int256 linearVariation = speed * int256(elapsed);
            uint256 variationMultiplier = MathLib.wExp(linearVariation);
            // endRateAtTarget is bounded between MIN_RATE_AT_TARGET and MAX_RATE_AT_TARGET.
            uint256 endRateAtTarget =
                startRateAtTarget.wMulDown(variationMultiplier).bound(MIN_RATE_AT_TARGET, MAX_RATE_AT_TARGET);
            uint256 endBorrowRate = _curve(endRateAtTarget, err);

            // Then we compute the average rate over the period.
            // Note that startBorrowRate is defined in the computations below.
            // avgBorrowRate = 1 / elapsed * ∫ startBorrowRate * exp(speed * t) dt between 0 and elapsed
            //               = startBorrowRate * (exp(linearVariation) - 1) / linearVariation
            //               = (endBorrowRate - startBorrowRate) / linearVariation
            // And avgBorrowRate ~ startBorrowRate = endBorrowRate for linearVariation around zero.
            // Also, when it is the first interaction (rateAtTarget = 0).
            uint256 avgBorrowRate;
            if (linearVariation == 0) {
                avgBorrowRate = endBorrowRate;
            } else {
                uint256 startBorrowRate = _curve(startRateAtTarget, err);
                // Safe "unchecked" cast to uint256 because linearVariation < 0 <=> variationMultiplier <= 1.
                //                                                              <=> endBorrowRate <= startBorrowRate.
                avgBorrowRate = uint256((int256(endBorrowRate) - int256(startBorrowRate)).wDivDown(linearVariation));
            }

            return (avgBorrowRate, endRateAtTarget);
        }
    }

    /// @dev Returns the rate for a given `_rateAtTarget` and an `err`.
    /// The formula of the curve is the following:
    /// r = ((1-1/C)*err + 1) * rateAtTarget if err < 0
    ///     ((C-1)*err + 1) * rateAtTarget else.
    function _curve(uint256 _rateAtTarget, int256 err) private view returns (uint256) {
        uint256 coeff = err < 0 ? WAD - WAD.wDivDown(CURVE_STEEPNESS) : CURVE_STEEPNESS - WAD;

        // Safe "unchecked" cast because err >= -1 (in WAD).
        return uint256(coeff.wMulDown(err) + WAD_INT).wMulDown(_rateAtTarget);
    }
}
