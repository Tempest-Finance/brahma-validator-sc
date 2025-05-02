// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { Address } from '@openzeppelin/contracts/utils/Address.sol';
import { ValidatorBase } from 'src/base/ValidatorBase.sol';
import { IPositionManager } from 'src/interfaces/IPositionManager.sol';
import { IShadowPositionManager } from 'src/interfaces/IShadowPositionManager.sol';
import { IShadowRouter } from 'src/interfaces/IShadowRouter.sol';
import { IShadowPool } from 'src/interfaces/IShadowPool.sol';
import { IShadowValidator } from 'src/interfaces/IShadowValidator.sol';
import { PoolAddress as PoolAddressShadow } from 'src/libraries/PoolAddressShadow.sol';
import { IValidator } from 'src/interfaces/IValidator.sol';
import { BytesLib } from 'src/libraries/BytesLib.sol';

/**
 * @title ShadowValidator (Base)
 * @notice Abstract contract providing validation logic specific to the Shadow protocol.
 * @dev Inherits from ValidatorBase and is intended to be inherited by the final Validator contract.
 */
abstract contract ShadowValidator is ValidatorBase, IShadowValidator {
    /**
     * @notice Validates parameters for minting a new position on Shadow.
     * @dev Checks recipient and pool price deviation.
     * @param target The Shadow Position Manager address.
     * @param data Abi-encoded IShadowPositionManager.MintParams.
     * @param configData Abi-encoded devPriceThresholdBps (uint256).
     */
    function validateMintShadow(address target, bytes memory data, bytes memory configData) public view {
        IShadowPositionManager.MintParams memory params = abi.decode(data, (IShadowPositionManager.MintParams));
        require(params.recipient == msg.sender, InvalidRecipient());

        uint256 devPriceThresholdBps = abi.decode(configData, (uint256));
        _validatePoolPriceShadow(target, params.token0, params.token1, params.tickSpacing, devPriceThresholdBps);
    }

    /**
     * @notice Validates parameters for an exactInputSingle swap on Shadow Router.
     * @dev Checks recipient and swap slippage.
     * @param target The Shadow Router address.
     * @param data Abi-encoded IShadowRouter.ExactInputSingleParams.
     * @param configData Abi-encoded maxSlippageBps (uint256).
     */
    function validateExactInputSingleShadow(address target, bytes memory data, bytes memory configData) public view {
        IShadowRouter.ExactInputSingleParams memory params = abi.decode(data, (IShadowRouter.ExactInputSingleParams));
        require(params.recipient == msg.sender, InvalidRecipient());

        uint256 maxSlippageBps = abi.decode(configData, (uint256));
        _checkSwapSlippage(params.tokenIn, params.tokenOut, params.amountIn, params.amountOutMinimum, maxSlippageBps);
    }

    /**
     * @notice Validates parameters for increasing liquidity on Shadow.
     * @dev Checks pool price deviation based on tokenId.
     * @param target The Shadow Position Manager address.
     * @param data Abi-encoded tokenId (uint256) or IncreaseLiquidityParams.
     * @param configData Abi-encoded devPriceThresholdBps (uint256).
     */
    function validateIncreaseLiquidityShadow(address target, bytes memory data, bytes memory configData) public view {
        // Decode the full params struct
        IPositionManager.IncreaseLiquidityParams memory params = abi.decode(
            data,
            (IPositionManager.IncreaseLiquidityParams)
        );
        uint256 devPriceThresholdBps = abi.decode(configData, (uint256));
        // Use the tokenId from the decoded params
        _validatePoolPriceFromTokenIdShadow(target, params.tokenId, devPriceThresholdBps);
    }

    /**
     * @notice Validates parameters for decreasing liquidity on Shadow.
     * @dev Checks pool price deviation based on tokenId.
     * @param target The Shadow Position Manager address.
     * @param data Abi-encoded tokenId (uint256) or DecreaseLiquidityParams.
     * @param configData Abi-encoded devPriceThresholdBps (uint256).
     */
    function validateDecreaseLiquidityShadow(address target, bytes memory data, bytes memory configData) public view {
        // Decode the full params struct
        IPositionManager.DecreaseLiquidityParams memory params = abi.decode(
            data,
            (IPositionManager.DecreaseLiquidityParams)
        );
        uint256 devPriceThresholdBps = abi.decode(configData, (uint256));
        // Use the tokenId from the decoded params
        _validatePoolPriceFromTokenIdShadow(target, params.tokenId, devPriceThresholdBps);
    }

    /**
     * @notice Validates parameters for collecting fees on Shadow.
     * @dev Checks recipient and pool price deviation based on tokenId.
     * @param target The Shadow Position Manager address.
     * @param data Abi-encoded IPositionManager.CollectParams.
     * @param configData Abi-encoded devPriceThresholdBps (uint256).
     */
    function validateCollectShadow(address target, bytes memory data, bytes memory configData) public view {
        IPositionManager.CollectParams memory params = abi.decode(data, (IPositionManager.CollectParams));
        require(params.recipient == msg.sender, InvalidRecipient());

        uint256 devPriceThresholdBps = abi.decode(configData, (uint256));
        _validatePoolPriceFromTokenIdShadow(target, params.tokenId, devPriceThresholdBps);
    }

    /**
     * @notice Internal helper to validate pool price based on tokenId for Shadow.
     * @param target The Shadow Position Manager address.
     * @param tokenId The NFT token ID representing the position.
     * @param devPriceThresholdBps Maximum allowed deviation in BPS.
     */
    function _validatePoolPriceFromTokenIdShadow(
        address target,
        uint256 tokenId,
        uint256 devPriceThresholdBps
    ) internal view {
        // Get position data via interface call
        (address token0, address token1, int24 tickSpacing, , , , , , , ) = IShadowPositionManager(target).positions(
            tokenId
        );

        // Validate price using the specific helper
        _validatePoolPriceShadow(target, token0, token1, tickSpacing, devPriceThresholdBps);
    }

    /**
     * @notice Validates the pool price for a Shadow pool against oracle price deviation.
     * @param positionManager The Shadow Position Manager address.
     * @param token0 Address of token0.
     * @param token1 Address of token1.
     * @param tickSpacing Tick spacing of the pool.
     * @param devPriceThresholdBps Maximum allowed deviation in BPS.
     */
    function _validatePoolPriceShadow(
        address positionManager,
        address token0,
        address token1,
        int24 tickSpacing,
        uint256 devPriceThresholdBps
    ) internal view {
        uint160 sqrtPoolPriceX96 = _getPoolPriceX96Shadow(positionManager, token0, token1, tickSpacing);
        _checkPriceDeviation(token0, token1, sqrtPoolPriceX96, devPriceThresholdBps);
    }

    /**
     * @notice Gets the sqrtPriceX96 for a Shadow pool.
     * @param positionManager The Shadow Position Manager address.
     * @param token0 Address of token0.
     * @param token1 Address of token1.
     * @param tickSpacing Tick spacing of the pool.
     * @return sqrtPriceX96 The sqrt price ratio X96 from the pool's slot0.
     */
    function _getPoolPriceX96Shadow(
        address positionManager,
        address token0,
        address token1,
        int24 tickSpacing
    ) internal view returns (uint160) {
        address deployer = IShadowPositionManager(positionManager).deployer();
        address poolAddress = PoolAddressShadow._computeAddress(
            deployer,
            PoolAddressShadow._getPoolKey(token0, token1, tickSpacing)
        );
        (uint160 sqrtPriceX96, , , , , , ) = IShadowPool(poolAddress).slot0();
        return sqrtPriceX96;
    }

    /// @notice get position data from position manager
    /// @dev the position returned from interface is contains more data than needed
    /// and causes stack too deep errors
    /// this function is used to get the position data from the position manager
    /// and return the token0, token1, and tickSpacing
    function _getPositionShadow(
        address positionManager,
        uint256 tokenId
    ) internal view returns (address token0, address token1, int24 tickSpacing) {
        bytes memory positionData = Address.functionStaticCall(
            positionManager,
            abi.encodeWithSelector(IShadowPositionManager.positions.selector, tokenId)
        );
        // trim the position data to the needed data
        // see IShadowPositionManager.positions for more details
        bytes memory trimmedPositionData = BytesLib._slice(positionData, 0, 32 * 3);
        return abi.decode(trimmedPositionData, (address, address, int24));
    }
}
