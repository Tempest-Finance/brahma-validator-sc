// SPDX-License-Identifier: MIT

pragma solidity >=0.8.24;

import { IValidator } from 'src/interfaces/IValidator.sol';
import { IOracleRegistry } from 'src/interfaces/IOracleRegistry.sol';
import { IOracleAdapter } from 'src/interfaces/IOracleAdapter.sol';
import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';

abstract contract ValidatorBase is IValidator {
    // Struct to hold oracle price and decimals
    struct OraclePrice {
        uint256 price;
        uint8 decimals;
    }

    uint256 internal constant _BASE = 10_000;

    // Mapping from validation key (target + external selector) to its configuration
    // Changed from private to internal for potential future flexibility, though unlikely needed.
    mapping(bytes32 => ValidationConfig) internal _validationConfigs;

    // Mapping from token pair (token0 + token1) to its oracle address
    mapping(bytes32 => address) private _oracles;

    /// @notice Registers a new oracle for token pair
    function _registerOracle(address token0, address token1, address adapter) internal {
        _oracles[keccak256(abi.encodePacked(token0, token1))] = adapter;
    }

    /// @notice Returns registered oracle of the pair
    function _getOracle(address token0, address token1) internal view returns (address) {
        return _oracles[keccak256(abi.encodePacked(token0, token1))];
    }

    /**
     * @notice Registers or updates the validation configuration for a given target and external selector.
     * @param target The contract address where the external function is called.
     * @param externalSelector The selector of the external function being validated.
     * @param selfSelector The selector of the internal validation function within this contract (or inheritors) to execute.
     * @param configData Encoded configuration data needed by the internal validation function.
     */
    // Updated signature and implementation logic
    function _registerValidation(
        address target,
        bytes4 externalSelector,
        bytes4 selfSelector,
        bytes memory configData
    ) internal {
        _validationConfigs[_validationKey(target, externalSelector)] = ValidationConfig({
            selfSelector: selfSelector, // Correctly assign the internal selector
            configData: configData
        });
    }

    /**
     * @notice Generates a unique key for storing validation configurations.
     * @param target The target contract address.
     * @param selector The external function selector.
     * @return A unique identifier based on the target and selector.
     */
    function _validationKey(address target, bytes4 selector) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(target, selector));
    }

    /**
     * @notice Fetches the latest price and decimals from the configured oracle registry for a token pair.
     * @dev Reverts if tokens are not in order (token0 < token1) or if no oracle exists.
     * @param token0 The address of the first token.
     * @param token1 The address of the second token.
     */
    function _getPrice(address token0, address token1) internal view returns (OraclePrice memory) {
        require(token0 < token1, OraclePairOrder());

        address oracle = _getOracle(token0, token1);
        require(oracle != address(0), NoOracle());

        uint256 price = uint256(IOracleAdapter(oracle).latestAnswer());
        uint8 decimals = IOracleAdapter(oracle).decimals();

        return OraclePrice({ price: price, decimals: decimals });
    }

    /**
     * @notice Checks if the pool price deviates from the oracle price beyond a specified threshold.
     * @dev Reverts with PriceDeviationExceeded if deviation is too high.
     * @param token0 Address of token0 (must be < token1).
     * @param token1 Address of token1.
     * @param sqrtPoolPriceX96 The current sqrt price ratio X96 from the pool.
     * @param devPriceThresholdBps The maximum allowed deviation in basis points (1% = 100 BPS).
     */
    function _checkPriceDeviation(
        address token0,
        address token1,
        uint160 sqrtPoolPriceX96,
        uint256 devPriceThresholdBps
    ) internal view {
        // If threshold is 0, skip the check entirely
        if (devPriceThresholdBps == 0) {
            return;
        }

        OraclePrice memory oraclePrice = _getPrice(token0, token1);

        // Calculate pool price normalized to oracle decimals
        // Based on: poolPrice = (sqrtPoolPriceX96 / 2^96)^2 * 10^oracleDecimals * 10^token0Decimals / 10^token1Decimals
        uint256 decimals0 = IERC20Metadata(token0).decimals();
        uint256 decimals1 = IERC20Metadata(token1).decimals();

        // Use single mulDiv for precision, matching original logic
        uint256 poolPriceInDecimals = Math.mulDiv(
            uint256(sqrtPoolPriceX96) * (10 ** oraclePrice.decimals), // sqrtPriceX96 scaled by oracle decimals
            uint256(sqrtPoolPriceX96) * (10 ** decimals0), // sqrtPriceX96 scaled by token0 decimals
            (uint256(1) << 192) * (10 ** decimals1) // 2^192 scaled by token1 decimals
        );

        // Calculate absolute difference
        uint256 diff = poolPriceInDecimals > oraclePrice.price
            ? poolPriceInDecimals - oraclePrice.price
            : oraclePrice.price - poolPriceInDecimals;

        // Calculate allowed deviation
        uint256 allowedDeviation = Math.mulDiv(oraclePrice.price, devPriceThresholdBps, _BASE);

        // Revert if deviation exceeds threshold
        require(diff <= allowedDeviation, PriceDeviationExceeded());
    }

    /**
     * @notice Checks if the minimum output amount for a swap respects the maximum allowed slippage based on oracle price.
     * @dev Reverts with SlippageExceeded if minAmountOut is too low, or SlippageTooHigh if maxSlippageBps > 10000.
     * @param tokenIn Address of the input token.
     * @param tokenOut Address of the output token.
     * @param amountIn Amount of tokenIn being swapped.
     * @param minAmountOut Minimum amount of tokenOut expected.
     * @param maxSlippageBps Maximum allowed slippage in basis points (1% = 100 BPS).
     */
    function _checkSwapSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 maxSlippageBps
    ) internal view {
        require(maxSlippageBps < _BASE, SlippageTooHigh());

        (address token0, address token1) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        OraclePrice memory oraclePrice = _getPrice(token0, token1);

        uint256 decimalsIn = IERC20Metadata(tokenIn).decimals();
        uint256 decimalsOut = IERC20Metadata(tokenOut).decimals();
        uint256 expectedAmountOut;

        if (tokenIn == token0) {
            // Selling token0 for token1: amountIn * oraclePrice / 10^oracleDecimals * 10^decimalsOut / 10^decimalsIn
            expectedAmountOut = Math.mulDiv(
                amountIn * (10 ** decimalsOut),
                oraclePrice.price,
                (10 ** oraclePrice.decimals) * (10 ** decimalsIn)
            );
        } else {
            // Selling token1 for token0: amountIn * 10^oracleDecimals / oraclePrice * 10^decimalsOut / 10^decimalsIn
            expectedAmountOut = Math.mulDiv(
                amountIn,
                (10 ** oraclePrice.decimals) * (10 ** decimalsOut),
                oraclePrice.price * (10 ** decimalsIn)
            );
        }

        // Calculate minimum accepted amount based on slippage
        uint256 minAmountOutAccepted = Math.mulDiv(expectedAmountOut, _BASE - maxSlippageBps, _BASE);

        // Revert if actual minimum is less than accepted minimum
        require(minAmountOut >= minAmountOutAccepted, SlippageExceeded());
    }
}
