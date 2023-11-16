// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IIrm} from "../lib/morpho-blue/src/interfaces/IIrm.sol";

import {UtilsLib} from "./libraries/UtilsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {MathLib, WAD_INT as WAD} from "./libraries/MathLib.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Id, MarketParams, Market} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MathLib as MorphoMathLib} from "../lib/morpho-blue/src/libraries/MathLib.sol";

/// @dev Number of steps used in the Riemann sum.
/// @dev 4 steps allows to have a relative error below 30% for 15 days at err=1 or err=-1.
int256 constant N_STEPS = 4;

/// @title AdaptativeCurveIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.org
contract AdaptativeCurveIrm is IIrm {
    using MathLib for int256;
    using UtilsLib for int256;
    using MorphoMathLib for uint128;
    using MorphoMathLib for uint256;
    using MarketParamsLib for MarketParams;

    /* EVENTS */

    /// @notice Emitted when a borrow rate is updated.
    event BorrowRateUpdate(Id indexed id, uint256 avgBorrowRate, uint256 rateAtTarget);

    /* CONSTANTS */

    /// @notice Maximum rate at target per second (scaled by WAD) (1B% APR).
    int256 public constant MAX_RATE_AT_TARGET = int256(0.01e9 ether) / 365 days;
    /// @notice Mininimum rate at target per second (scaled by WAD) (0.1% APR).
    int256 public constant MIN_RATE_AT_TARGET = int256(0.001 ether) / 365 days;
    /// @notice Address of Morpho.
    address public immutable MORPHO;
    /// @notice Curve steepness (scaled by WAD).
    /// @dev Verified to be greater than 1 at construction.
    int256 public immutable CURVE_STEEPNESS;
    /// @notice Adjustment speed (scaled by WAD).
    /// @dev The speed is per second, so the rate moves at a speed of ADJUSTMENT_SPEED * err each second (while being
    /// continuously compounded). A typical value for the ADJUSTMENT_SPEED would be 10 ethers / 365 days.
    /// @dev Verified to be non-negative at construction.
    int256 public immutable ADJUSTMENT_SPEED;
    /// @notice Target utilization (scaled by WAD).
    /// @dev Verified to be strictly between 0 and 1 at construction.
    int256 public immutable TARGET_UTILIZATION;
    /// @notice Initial rate at target per second (scaled by WAD).
    /// @dev Verified to be between MIN_RATE_AT_TARGET and MAX_RATE_AT_TARGET at contruction.
    int256 public immutable INITIAL_RATE_AT_TARGET;

    /* STORAGE */

    /// @notice Rate at target utilization.
    /// @dev Tells the height of the curve.
    mapping(Id => int256) public rateAtTarget;

    /* CONSTRUCTOR */

    /// @notice Constructor.
    /// @param morpho The address of Morpho.
    /// @param curveSteepness The curve steepness (scaled by WAD).
    /// @param adjustmentSpeed The adjustment speed (scaled by WAD).
    /// @param targetUtilization The target utilization (scaled by WAD).
    /// @param initialRateAtTarget The initial rate at target (scaled by WAD).
    constructor(
        address morpho,
        int256 curveSteepness,
        int256 adjustmentSpeed,
        int256 targetUtilization,
        int256 initialRateAtTarget
    ) {
        require(morpho != address(0), ErrorsLib.ZERO_ADDRESS);
        require(curveSteepness >= WAD, ErrorsLib.INPUT_TOO_SMALL);
        require(adjustmentSpeed >= 0, ErrorsLib.INPUT_TOO_SMALL);
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
        (uint256 avgRate,) = _borrowRate(marketParams.id(), market);
        return avgRate;
    }

    /// @inheritdoc IIrm
    function borrowRate(MarketParams memory marketParams, Market memory market) external returns (uint256) {
        require(msg.sender == MORPHO, ErrorsLib.NOT_MORPHO);

        Id id = marketParams.id();

        (uint256 avgRate, int256 endRateAtTarget) = _borrowRate(id, market);

        rateAtTarget[id] = endRateAtTarget;

        // Safe "unchecked" because endRateAtTarget >= 0.
        emit BorrowRateUpdate(id, avgRate, uint256(endRateAtTarget));

        return avgRate;
    }

    /// @dev Returns avgRate and endRateAtTarget.
    /// @dev Assumes that the inputs `marketParams` and `id` match.
    function _borrowRate(Id id, Market memory market) private view returns (uint256, int256) {
        // Safe "unchecked" cast because the utilization is smaller than 1 (scaled by WAD).
        int256 utilization =
            int256(market.totalSupplyAssets > 0 ? market.totalBorrowAssets.wDivDown(market.totalSupplyAssets) : 0);

        int256 errNormFactor = utilization > TARGET_UTILIZATION ? WAD - TARGET_UTILIZATION : TARGET_UTILIZATION;
        int256 err = (utilization - TARGET_UTILIZATION).wDivDown(errNormFactor);

        int256 startRateAtTarget = rateAtTarget[id];

        if (startRateAtTarget == 0) {
            // First interaction.
            // Safe "unchecked" cast because INITIAL_RATE_AT_TARGET >= 0.
            return (uint256(_curve(INITIAL_RATE_AT_TARGET, err)), INITIAL_RATE_AT_TARGET);
        } else {
            // Note that the speed is assumed constant between two interactions, but in theory it increases because of
            // interests. So the rate will be slightly underestimated.
            int256 speed = ADJUSTMENT_SPEED.wMulDown(err);
            // market.lastUpdate != 0 because it is not the first interaction with this market.
            // Safe "unchecked" cast because block.timestamp - market.lastUpdate <= block.timestamp <= type(int256).max.
            int256 elapsed = int256(block.timestamp - market.lastUpdate);
            int256 linearAdaptation = speed * elapsed;

            // We want to approximate an average of the rate over the period [0, T]:
            // avg = 1/T ∫_0^T curve(startRateAtTarget * exp(speed * x), err) dx
            // We approximate the integral with a Riemann sum (steps of length T/N). We want to underestimate the rate,
            // which means doing a left Riemann (a=0, b=N-1) when the rate goes up (err>0) and a right Riemann (a=1,
            // b=N) when the rate goes down (err<0).
            // avg ~= 1/T Σ_i=a^b curve(startRateAtTarget * exp(speed * T/N * i), err) * T / N
            //     ~= Σ_i=a^b curve(startRateAtTarget * exp(linearVariation/N * i), err) / N
            // curve is linear in startRateAtTarget, so:
            //     ~= curve(Σ_i=a^b startRateAtTarget * exp(linearVariation/N * i), err) / N
            //     ~= curve(Σ_i=a^b startRateAtTarget * exp(linearVariation/N * i) / N, err)
            int256 sumRateAtTarget;
            int256 step = linearAdaptation / N_STEPS;
            // Compute the terms 1 to N_STEPS - 1.
            for (int256 k = 1; k < N_STEPS; k++) {
                sumRateAtTarget += _newRateAtTarget(startRateAtTarget, step * k);
            }
            int256 endRateAtTarget = _newRateAtTarget(startRateAtTarget, linearAdaptation);
            // Add the term 0 of N_STEPS depending of if we do a left or right Riemann.
            sumRateAtTarget += err < 0 ? endRateAtTarget : startRateAtTarget;
            int256 avgRateAtTarget = sumRateAtTarget / N_STEPS;

            // Safe "unchecked" cast because avgRateAtTarget >= 0.
            return (uint256(_curve(avgRateAtTarget, err)), endRateAtTarget);
        }
    }

    /// @dev Returns the rate for a given `_rateAtTarget` and an `err`.
    /// The formula of the curve is the following:
    /// r = ((1-1/C)*err + 1) * rateAtTarget if err < 0
    ///     ((C-1)*err + 1) * rateAtTarget else.
    function _curve(int256 _rateAtTarget, int256 err) private view returns (int256) {
        // Non negative because 1 - 1/C >= 0, C - 1 >= 0.
        int256 coeff = err < 0 ? WAD - WAD.wDivDown(CURVE_STEEPNESS) : CURVE_STEEPNESS - WAD;
        // Non negative if _rateAtTarget >= 0 because if err < 0, coeff <= 1.
        return (coeff.wMulDown(err) + WAD).wMulDown(int256(_rateAtTarget));
    }

    /// @dev Returns the new rate at target, for a given `startRateAtTarget` and a given `linearAdaptation`.
    /// The formula is: max(min(startRateAtTarget * exp(linearAdaptation), maxRateAtTarget), minRateAtTarget).
    function _newRateAtTarget(int256 startRateAtTarget, int256 linearAdaptation) private pure returns (int256) {
        // Non negative because MIN_RATE_AT_TARGET > 0.
        return startRateAtTarget.wMulDown(MathLib.wExp(linearAdaptation)).bound(MIN_RATE_AT_TARGET, MAX_RATE_AT_TARGET);
    }
}
