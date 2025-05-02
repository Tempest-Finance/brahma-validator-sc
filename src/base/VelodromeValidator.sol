// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { Address } from '@openzeppelin/contracts/utils/Address.sol';
import { ValidatorBase } from 'src/base/ValidatorBase.sol';
import { IPositionManager } from 'src/interfaces/IPositionManager.sol';
import { IVelodromePositionManager } from 'src/interfaces/IVelodromePositionManager.sol';
import { IVelodromeRouter } from 'src/interfaces/IVelodromeRouter.sol';
import { IVelodromePool } from 'src/interfaces/IVelodromePool.sol';
import { PoolAddress as PoolAddressVelodrome } from 'src/libraries/PoolAddressVelodrome.sol';
import { IValidator } from 'src/interfaces/IValidator.sol'; // For errors
import { BytesLib } from 'src/libraries/BytesLib.sol';

/**
 * @title VelodromeValidator (Base)
 * @notice Abstract contract providing validation logic specific to the Velodrome protocol.
 * @dev Inherits from ValidatorBase and is intended to be inherited by the final Validator contract.
 */
abstract contract VelodromeValidator is ValidatorBase {
    /**
     * @notice Validates parameters for minting a new position on Velodrome.
     * @dev Checks recipient and pool price deviation.
     * @param target The Velodrome Position Manager address.
     * @param data Abi-encoded IVelodromePositionManager.MintParams.
     * @param configData Abi-encoded devPriceThresholdBps (uint256).
     */
    function validateMintVelodrome(address target, bytes memory data, bytes memory configData) public view {
        IVelodromePositionManager.MintParams memory params = abi.decode(data, (IVelodromePositionManager.MintParams));
        require(params.recipient == msg.sender, InvalidRecipient());

        uint256 devPriceThresholdBps = abi.decode(configData, (uint256));
        _validatePoolPriceVelodrome(target, params.token0, params.token1, params.tickSpacing, devPriceThresholdBps);
    }

    /**
     * @notice Validates parameters for an exactInputSingle swap on Velodrome Router.
     * @dev Checks recipient and swap slippage. Uses IShadowRouter.ExactInputSingleParams struct shape.
     * @param target The Velodrome Router address.
     * @param data Abi-encoded IShadowRouter.ExactInputSingleParams.
     * @param configData Abi-encoded maxSlippageBps (uint256).
     */
    function validateExactInputSingleVelodrome(address target, bytes memory data, bytes memory configData) public view {
        IVelodromeRouter.ExactInputSingleParams memory params = abi.decode(
            data,
            (IVelodromeRouter.ExactInputSingleParams)
        );
        require(params.recipient == msg.sender, InvalidRecipient());

        uint256 maxSlippageBps = abi.decode(configData, (uint256));
        _checkSwapSlippage(params.tokenIn, params.tokenOut, params.amountIn, params.amountOutMinimum, maxSlippageBps);
    }

    /**
     * @notice Validates parameters for increasing liquidity on Velodrome.
     * @dev Checks pool price deviation based on tokenId.
     * @param target The Velodrome Position Manager address.
     * @param data Abi-encoded tokenId (uint256) or IncreaseLiquidityParams.
     * @param configData Abi-encoded devPriceThresholdBps (uint256).
     */
    function validateIncreaseLiquidityVelodrome(
        address target,
        bytes memory data,
        bytes memory configData
    ) public view {
        // Decode the full params struct
        IPositionManager.IncreaseLiquidityParams memory params = abi.decode(
            data,
            (IPositionManager.IncreaseLiquidityParams)
        );
        uint256 devPriceThresholdBps = abi.decode(configData, (uint256));
        // Use the tokenId from the decoded params
        _validatePoolPriceFromTokenIdVelodrome(target, params.tokenId, devPriceThresholdBps);
    }

    /**
     * @notice Validates parameters for decreasing liquidity on Velodrome.
     * @dev Checks pool price deviation based on tokenId.
     * @param target The Velodrome Position Manager address.
     * @param data Abi-encoded tokenId (uint256) or DecreaseLiquidityParams.
     * @param configData Abi-encoded devPriceThresholdBps (uint256).
     */
    function validateDecreaseLiquidityVelodrome(
        address target,
        bytes memory data,
        bytes memory configData
    ) public view {
        // Decode the full params struct
        IPositionManager.DecreaseLiquidityParams memory params = abi.decode(
            data,
            (IPositionManager.DecreaseLiquidityParams)
        );
        uint256 devPriceThresholdBps = abi.decode(configData, (uint256));
        // Use the tokenId from the decoded params
        _validatePoolPriceFromTokenIdVelodrome(target, params.tokenId, devPriceThresholdBps);
    }

    /**
     * @notice Validates parameters for collecting fees on Velodrome.
     * @dev Checks recipient and pool price deviation based on tokenId.
     * @param target The Velodrome Position Manager address.
     * @param data Abi-encoded IPositionManager.CollectParams.
     * @param configData Abi-encoded devPriceThresholdBps (uint256).
     */
    function validateCollectVelodrome(address target, bytes memory data, bytes memory configData) public view {
        IPositionManager.CollectParams memory params = abi.decode(data, (IPositionManager.CollectParams));
        require(params.recipient == msg.sender, InvalidRecipient());

        uint256 devPriceThresholdBps = abi.decode(configData, (uint256));
        _validatePoolPriceFromTokenIdVelodrome(target, params.tokenId, devPriceThresholdBps);
    }

    /**
     * @notice Internal helper to validate pool price based on tokenId for Velodrome.
     * @param target The Velodrome Position Manager address.
     * @param tokenId The NFT token ID representing the position.
     * @param devPriceThresholdBps Maximum allowed deviation in BPS.
     */
    function _validatePoolPriceFromTokenIdVelodrome(
        address target,
        uint256 tokenId,
        uint256 devPriceThresholdBps
    ) internal view {
        // Get position data via interface call
        (address token0, address token1, int24 tickSpacing) = _getPositionVelodrome(target, tokenId);
        // Validate price using the specific helper
        _validatePoolPriceVelodrome(target, token0, token1, tickSpacing, devPriceThresholdBps);
    }

    /**
     * @notice Validates the pool price for a Velodrome pool against oracle price deviation.
     * @param positionManager The Velodrome Position Manager address.
     * @param token0 Address of token0.
     * @param token1 Address of token1.
     * @param tickSpacing Tick spacing of the pool.
     * @param devPriceThresholdBps Maximum allowed deviation in BPS.
     */
    function _validatePoolPriceVelodrome(
        address positionManager,
        address token0,
        address token1,
        int24 tickSpacing,
        uint256 devPriceThresholdBps
    ) internal view {
        uint160 sqrtPoolPriceX96 = _getPoolPriceX96Velodrome(positionManager, token0, token1, tickSpacing);
        _checkPriceDeviation(token0, token1, sqrtPoolPriceX96, devPriceThresholdBps);
    }

    /**
     * @notice Gets the sqrtPriceX96 for a Velodrome pool.
     * @param positionManager The Velodrome Position Manager address.
     * @param token0 Address of token0.
     * @param token1 Address of token1.
     * @param tickSpacing Tick spacing of the pool.
     * @return sqrtPriceX96 The sqrt price ratio X96 from the pool's slot0.
     */
    function _getPoolPriceX96Velodrome(
        address positionManager,
        address token0,
        address token1,
        int24 tickSpacing
    ) internal view returns (uint160) {
        address factory = IVelodromePositionManager(positionManager).factory();
        address poolAddress = PoolAddressVelodrome._computeAddress(
            factory,
            PoolAddressVelodrome._getPoolKey(token0, token1, tickSpacing)
        );
        (uint160 sqrtPriceX96, , , , , ) = IVelodromePool(poolAddress).slot0();
        return sqrtPriceX96;
    }

    /// @notice get position data from position manager
    /// @dev the position returned from interface is contains more data than needed
    /// and causes stack too deep errors
    /// this function is used to get the position data from the position manager
    /// and return the token0, token1, and tickSpacing
    function _getPositionVelodrome(
        address positionManager,
        uint256 tokenId
    ) internal view returns (address token0, address token1, int24 tickSpacing) {
        bytes memory positionData = Address.functionStaticCall(
            positionManager,
            abi.encodeWithSelector(IVelodromePositionManager.positions.selector, tokenId)
        );
        // trim the position data to the needed data
        // see IVelodromePositionManager.positions for more details
        bytes memory trimmedPositionData = BytesLib._slice(positionData, 32 * 2, 32 * 3);
        return abi.decode(trimmedPositionData, (address, address, int24));
    }
}
