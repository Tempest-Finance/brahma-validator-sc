// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { Address } from '@openzeppelin/contracts/utils/Address.sol';
import { ValidatorBase } from 'src/base/ValidatorBase.sol';
import { IPositionManager } from 'src/interfaces/IPositionManager.sol';
import { IThenaPositionManager } from 'src/interfaces/IThenaPositionManager.sol';
import { IThenaRouter } from 'src/interfaces/IThenaRouter.sol';
import { IThenaPool } from 'src/interfaces/IThenaPool.sol';
import { PoolAddress as PoolAddressThena } from 'src/libraries/PoolAddressThena.sol';
import { IValidator } from 'src/interfaces/IValidator.sol'; // For errors
import { BytesLib } from 'src/libraries/BytesLib.sol';

/**
 * @title ThenaValidator (Base)
 * @notice Abstract contract providing validation logic specific to the Thena protocol.
 * @dev Inherits from ValidatorBase and is intended to be inherited by the final Validator contract.
 */
abstract contract ThenaValidator is ValidatorBase {
    /**
     * @notice Validates parameters for minting a new position on Thena.
     * @dev Checks recipient and pool price deviation.
     * @param target The Thena Position Manager address.
     * @param data Abi-encoded IThenaPositionManager.MintParams.
     * @param configData Abi-encoded devPriceThresholdBps (uint256).
     */
    function validateMintThena(address target, bytes memory data, bytes memory configData) public view {
        IThenaPositionManager.MintParams memory params = abi.decode(data, (IThenaPositionManager.MintParams));
        require(params.recipient == msg.sender, InvalidRecipient());

        uint256 devPriceThresholdBps = abi.decode(configData, (uint256));
        // Thena pools don't use tickSpacing in the same way for price checks
        _validatePoolPriceThena(target, params.token0, params.token1, devPriceThresholdBps);
    }

    /**
     * @notice Validates parameters for an exactInputSingle swap on Thena Router.
     * @dev Checks recipient and swap slippage.
     * @param target The Thena Router address.
     * @param data Abi-encoded IThenaRouter.ExactInputSingleParams.
     * @param configData Abi-encoded maxSlippageBps (uint256).
     */
    function validateExactInputSingleThena(address target, bytes memory data, bytes memory configData) public view {
        IThenaRouter.ExactInputSingleParams memory params = abi.decode(data, (IThenaRouter.ExactInputSingleParams));
        require(params.recipient == msg.sender, InvalidRecipient());

        uint256 maxSlippageBps = abi.decode(configData, (uint256));
        _checkSwapSlippage(params.tokenIn, params.tokenOut, params.amountIn, params.amountOutMinimum, maxSlippageBps);
    }

    /**
     * @notice Validates parameters for increasing liquidity on Thena.
     * @dev Checks pool price deviation based on tokenId.
     * @param target The Thena Position Manager address.
     * @param data Abi-encoded tokenId (uint256) or IncreaseLiquidityParams.
     * @param configData Abi-encoded devPriceThresholdBps (uint256).
     */
    function validateIncreaseLiquidityThena(address target, bytes memory data, bytes memory configData) public view {
        // Decode the full params struct
        IPositionManager.IncreaseLiquidityParams memory params = abi.decode(
            data,
            (IPositionManager.IncreaseLiquidityParams)
        );
        uint256 devPriceThresholdBps = abi.decode(configData, (uint256));
        // Use the tokenId from the decoded params
        _validatePoolPriceFromTokenIdThena(target, params.tokenId, devPriceThresholdBps);
    }

    /**
     * @notice Validates parameters for decreasing liquidity on Thena.
     * @dev Checks pool price deviation based on tokenId.
     * @param target The Thena Position Manager address.
     * @param data Abi-encoded tokenId (uint256) or DecreaseLiquidityParams.
     * @param configData Abi-encoded devPriceThresholdBps (uint256).
     */
    function validateDecreaseLiquidityThena(address target, bytes memory data, bytes memory configData) public view {
        // Decode the full params struct
        IPositionManager.DecreaseLiquidityParams memory params = abi.decode(
            data,
            (IPositionManager.DecreaseLiquidityParams)
        );
        uint256 devPriceThresholdBps = abi.decode(configData, (uint256));
        // Use the tokenId from the decoded params
        _validatePoolPriceFromTokenIdThena(target, params.tokenId, devPriceThresholdBps);
    }

    /**
     * @notice Validates parameters for collecting fees on Thena.
     * @dev Checks recipient and pool price deviation based on tokenId.
     * @param target The Thena Position Manager address.
     * @param data Abi-encoded IPositionManager.CollectParams.
     * @param configData Abi-encoded devPriceThresholdBps (uint256).
     */
    function validateCollectThena(address target, bytes memory data, bytes memory configData) public view {
        IPositionManager.CollectParams memory params = abi.decode(data, (IPositionManager.CollectParams));
        require(params.recipient == msg.sender, InvalidRecipient());

        uint256 devPriceThresholdBps = abi.decode(configData, (uint256));
        _validatePoolPriceFromTokenIdThena(target, params.tokenId, devPriceThresholdBps);
    }

    /**
     * @notice Internal helper to validate pool price based on tokenId for Thena.
     * @param target The Thena Position Manager address.
     * @param tokenId The NFT token ID representing the position.
     * @param devPriceThresholdBps Maximum allowed deviation in BPS.
     */
    function _validatePoolPriceFromTokenIdThena(
        address target,
        uint256 tokenId,
        uint256 devPriceThresholdBps
    ) internal view {
        // Get position data via interface call
        (address token0, address token1) = _getPositionThena(target, tokenId);
        // Validate price using the specific helper (doesn't need tickSpacing)
        _validatePoolPriceThena(target, token0, token1, devPriceThresholdBps);
    }

    /**
     * @notice Validates the pool price for a Thena pool against oracle price deviation.
     * @param positionManager The Thena Position Manager address.
     * @param token0 Address of token0.
     * @param token1 Address of token1.
     * @param devPriceThresholdBps Maximum allowed deviation in BPS.
     */
    function _validatePoolPriceThena(
        address positionManager,
        address token0,
        address token1,
        uint256 devPriceThresholdBps
    ) internal view {
        uint160 sqrtPoolPriceX96 = _getPoolPriceX96Thena(positionManager, token0, token1);
        _checkPriceDeviation(token0, token1, sqrtPoolPriceX96, devPriceThresholdBps);
    }

    /**
     * @notice Gets the sqrtPriceX96 for a Thena pool.
     * @param positionManager The Thena Position Manager address.
     * @param token0 Address of token0.
     * @param token1 Address of token1.
     * @return sqrtPriceX96 The sqrt price ratio X96 from the pool's globalState.
     */
    function _getPoolPriceX96Thena(
        address positionManager,
        address token0,
        address token1
    ) internal view returns (uint160) {
        address deployer = IThenaPositionManager(positionManager).poolDeployer();
        address poolAddress = PoolAddressThena._computeAddress(deployer, PoolAddressThena._getPoolKey(token0, token1));
        (uint160 sqrtPriceX96, , , , , , ) = IThenaPool(poolAddress).globalState();
        return sqrtPriceX96;
    }

    /// @notice get position data from position manager
    /// @dev the position returned from interface is contains more data than needed
    /// and causes stack too deep errors
    /// this function is used to get the position data from the position manager
    /// and return the token0, token1, and tickSpacing
    function _getPositionThena(
        address positionManager,
        uint256 tokenId
    ) internal view returns (address token0, address token1) {
        bytes memory positionData = Address.functionStaticCall(
            positionManager,
            abi.encodeWithSelector(IThenaPositionManager.positions.selector, tokenId)
        );
        // trim the position data to the needed data
        // see IThenaPositionManager.positions for more details
        bytes memory trimmedPositionData = BytesLib._slice(positionData, 32 * 2, 32 * 2);
        return abi.decode(trimmedPositionData, (address, address));
    }
}
