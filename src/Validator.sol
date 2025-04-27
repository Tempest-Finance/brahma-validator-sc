// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { Address } from '@openzeppelin/contracts/utils/Address.sol';
import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';

import { IPositionManager } from 'src/interfaces/IPositionManager.sol';
import { IShadowPool } from 'src/interfaces/IShadowPool.sol';
import { IShadowPositionManager, POSITION_RESULT_LENGTH as SHADOW_POSITION_RESULT_LENGTH } from 'src/interfaces/IShadowPositionManager.sol';
import { IShadowRouter } from 'src/interfaces/IShadowRouter.sol';
import { IThenaPool } from 'src/interfaces/IThenaPool.sol';
import { IThenaPositionManager, POSITION_RESULT_LENGTH as THENA_POSITION_RESULT_LENGTH } from 'src/interfaces/IThenaPositionManager.sol';
import { IThenaRouter } from 'src/interfaces/IThenaRouter.sol';
import { IValidator } from 'src/interfaces/IValidator.sol';
import { IVelodromePool } from 'src/interfaces/IVelodromePool.sol';
import { IVelodromePositionManager, POSITION_RESULT_LENGTH as VELODROME_POSITION_RESULT_LENGTH } from 'src/interfaces/IVelodromePositionManager.sol';
import { IVelodromeRouter } from 'src/interfaces/IVelodromeRouter.sol';

import { BytesLib } from 'src/libraries/BytesLib.sol';
import { OracleLib } from 'src/libraries/OracleLib.sol';
import { PoolAddress as PoolAddressShadow } from 'src/libraries/PoolAddressShadow.sol';
import { PoolAddress as PoolAddressThena } from 'src/libraries/PoolAddressThena.sol';
import { PoolAddress as PoolAddressVelodrome } from 'src/libraries/PoolAddressVelodrome.sol';

// Custom Errors
error PriceDeviationExceeded();
error SlippageExceeded();
error DelegateCallFailed();
error InvalidTransactionData();
error UnknownProtocolVariant(uint256 dataLength);
error InvalidProtocol();
error OracleFailure();
error InvalidRecipient();
error PoolDerivationFailed();
error PositionsCallFailed();
error InvalidPoolAddress();

contract Validator is IValidator {
    using Address for address;
    using BytesLib for bytes;

    uint256 private immutable _MAX_SLIPPAGE;
    uint256 private immutable _DEV_PRICE_THRESHOLD;
    address private immutable _MULTICALL_ADDRESS;

    uint256 private constant _BPS = 10000;

    constructor(address _internalMulticallAddress, uint256 _maxSlippage, uint256 _deviationPriceThreshold) {
        OracleLib.validateConfiguredOracles();
        _MAX_SLIPPAGE = _maxSlippage;
        _DEV_PRICE_THRESHOLD = _deviationPriceThreshold;
        _MULTICALL_ADDRESS = _internalMulticallAddress;
    }

    function multiSend(bytes calldata transactions) public payable {
        bytes memory _transactions = transactions;
        while (_transactions.length > 0) {
            // extracted call data
            bytes memory callData;
            address target;

            (_transactions, target, callData) = _extractTransaction(_transactions);

            _validateCall(target, callData);
        }

        _MULTICALL_ADDRESS.functionDelegateCall(abi.encodeWithSelector(IValidator.multiSend.selector, transactions));
    }

    function _extractTransaction(
        bytes memory transactions
    ) internal pure returns (bytes memory remaining, address target, bytes memory callData) {
        // [1-byte operation][20-byte address][32-byte value][32-byte data length][data]
        target = transactions.slice(1, 20).toAddress();
        // bytes memory value = BytesLib.slice(transactions, 21, 32);
        uint256 dataLength = transactions.slice(53, 32).toUint256();
        callData = transactions.slice(85, dataLength);
        (, remaining) = transactions.popHead(85 + dataLength);
    }

    function _validateCall(address target, bytes memory callData) internal view {
        // Extract 4-byte selector and remaining params
        (bytes4 selector, bytes memory paramsData) = callData.popHeadSelector();

        if (
            selector == IPositionManager.increaseLiquidity.selector ||
            selector == IPositionManager.decreaseLiquidity.selector
        ) {
            _validateIncreaseAndDecreaseLiquidity(target, paramsData);
        } else if (selector == IPositionManager.collect.selector) {
            _validateCollect(target, paramsData);
        } else if (
            selector == IShadowPositionManager.mint.selector ||
            selector == IThenaPositionManager.mint.selector ||
            selector == IVelodromePositionManager.mint.selector
        ) {
            _validateMint(target, paramsData, selector);
        } else if (
            // velodrome have same function selector with shadow.
            selector == IShadowRouter.exactInputSingle.selector || selector == IThenaRouter.exactInputSingle.selector
        ) {
            _validateExactInputSingle(target, paramsData, selector);
        }
    }

    function _validateIncreaseAndDecreaseLiquidity(address target, bytes memory paramsData) internal view {
        // tokenId is always at the start of the paramsData regardless signature
        (uint256 tokenId, ) = BytesLib.popHeadUint256(paramsData);

        _validatePoolPriceFromTokenId(target, tokenId);
    }

    function _validatePoolPrice(
        address positionManager,
        Protocol protocol,
        address token0,
        address token1,
        int24 tickSpacing
    ) internal view {
        uint160 poolPriceX96 = _getPoolPriceX96(positionManager, protocol, token0, token1, tickSpacing);

        OracleLib.OraclePrice memory oraclePrice = OracleLib.getPrice(token0, token1);

        // normalize pool price
        uint256 poolPriceInDecimals = Math.mulDiv(
            poolPriceX96 * 10 ** oraclePrice.decimals,
            poolPriceX96 * 10 ** IERC20Metadata(token0).decimals(),
            10 ** IERC20Metadata(token1).decimals() * 1 << 192
        );

        // calculate deviation
        uint256 diff = poolPriceInDecimals > oraclePrice.price
            ? poolPriceInDecimals - oraclePrice.price
            : oraclePrice.price - poolPriceInDecimals;

        // check threshold
        uint256 allowedDeviation = Math.mulDiv(oraclePrice.price, _DEV_PRICE_THRESHOLD, _BPS);

        // revert if deviation exceeds threshold
        if (diff > allowedDeviation) {
            revert PriceDeviationExceeded();
        }
    }

    function _validatePoolPriceFromTokenId(address positionManager, uint256 tokenId) internal view {
        bytes memory posReturnData = positionManager.functionStaticCall(
            abi.encodeWithSelector(IPositionManager.positions.selector, tokenId)
        );

        uint256 dataLength = posReturnData.length;

        address token0;
        address token1;
        int24 tickSpacing;
        Protocol protocol;

        if (dataLength == VELODROME_POSITION_RESULT_LENGTH) {
            IVelodromePositionManager.PositionData memory posData = abi.decode(
                posReturnData,
                (IVelodromePositionManager.PositionData)
            );
            token0 = posData.token0;
            token1 = posData.token1;
            tickSpacing = posData.tickSpacing;
            protocol = Protocol.Velodrome;
        } else if (dataLength == THENA_POSITION_RESULT_LENGTH) {
            IThenaPositionManager.PositionData memory posData = abi.decode(
                posReturnData,
                (IThenaPositionManager.PositionData)
            );
            token0 = posData.token0;
            token1 = posData.token1;
            tickSpacing = 0;
            protocol = Protocol.Thena;
        } else if (dataLength == SHADOW_POSITION_RESULT_LENGTH) {
            IShadowPositionManager.PositionData memory posData = abi.decode(
                posReturnData,
                (IShadowPositionManager.PositionData)
            );
            token0 = posData.token0;
            token1 = posData.token1;
            tickSpacing = posData.tickSpacing;
            protocol = Protocol.Shadow;
        } else {
            revert UnknownProtocolVariant(dataLength);
        }

        _validatePoolPrice(positionManager, protocol, token0, token1, tickSpacing);
    }

    function _validateCollect(address target, bytes memory paramsData) internal view {
        IPositionManager.CollectParams memory collectParams = abi.decode(paramsData, (IPositionManager.CollectParams));
        require(collectParams.recipient == address(this), InvalidRecipient());
        _validatePoolPriceFromTokenId(target, collectParams.tokenId);
    }

    function _validateMint(address target, bytes memory paramsData, bytes4 selector) internal view {
        address token0;
        address token1;
        int24 tickSpacing;
        address recipient;
        Protocol protocol;
        if (selector == IShadowPositionManager.mint.selector) {
            IShadowPositionManager.MintParams memory mintParams = abi.decode(
                paramsData,
                (IShadowPositionManager.MintParams)
            );
            token0 = mintParams.token0;
            token1 = mintParams.token1;
            tickSpacing = mintParams.tickSpacing;
            recipient = mintParams.recipient;
            protocol = Protocol.Shadow;
        } else if (selector == IThenaPositionManager.mint.selector) {
            IThenaPositionManager.MintParams memory mintParams = abi.decode(
                paramsData,
                (IThenaPositionManager.MintParams)
            );
            token0 = mintParams.token0;
            token1 = mintParams.token1;
            recipient = mintParams.recipient;
            protocol = Protocol.Thena;
        } else if (selector == IVelodromePositionManager.mint.selector) {
            IVelodromePositionManager.MintParams memory mintParams = abi.decode(
                paramsData,
                (IVelodromePositionManager.MintParams)
            );
            token0 = mintParams.token0;
            token1 = mintParams.token1;
            tickSpacing = mintParams.tickSpacing;
            recipient = mintParams.recipient;
            protocol = Protocol.Velodrome;
        } else {
            revert InvalidProtocol();
        }
        require(recipient == address(this), InvalidRecipient());
        _validatePoolPrice(target, protocol, token0, token1, tickSpacing);
    }

    function _validateExactInputSingle(address router, bytes memory paramsData, bytes4 selector) internal view {
        uint160 sqrtPriceX96;
        address recipient;
        address token0;
        address token1;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        if (selector == IThenaRouter.exactInputSingle.selector) {
            IThenaRouter.ExactInputSingleParams memory params = abi.decode(
                paramsData,
                (IThenaRouter.ExactInputSingleParams)
            );
            (token0, token1) = params.tokenIn < params.tokenOut
                ? (params.tokenIn, params.tokenOut)
                : (params.tokenOut, params.tokenIn);

            address pool = PoolAddressThena.computeAddress(
                IThenaRouter(router).poolDeployer(),
                PoolAddressThena.getPoolKey(token0, token1)
            );
            (sqrtPriceX96, , , , , , ) = IThenaPool(pool).globalState();
            recipient = params.recipient;
            tokenIn = params.tokenIn;
            tokenOut = params.tokenOut;
            amountIn = params.amountIn;
            minAmountOut = params.amountOutMinimum;
        } else {
            // shadow and velo has same struct to decode. this decode cover both case shadow and velo
            IShadowRouter.ExactInputSingleParams memory params = abi.decode(
                paramsData,
                (IShadowRouter.ExactInputSingleParams)
            );
            (token0, token1) = params.tokenIn < params.tokenOut
                ? (params.tokenIn, params.tokenOut)
                : (params.tokenOut, params.tokenIn);

            bool isShadow = false;
            {
                address shadowPool = PoolAddressShadow.computeAddress(
                    IShadowRouter(router).deployer(),
                    PoolAddressShadow.getPoolKey(token0, token1, params.tickSpacing)
                );

                if (_isContract(shadowPool)) {
                    (sqrtPriceX96, , , , , , ) = IShadowPool(shadowPool).slot0();
                    isShadow = true;
                }
            }
            if (!isShadow) {
                address veloPool = PoolAddressVelodrome.computeAddress(
                    IVelodromeRouter(router).factory(),
                    PoolAddressVelodrome.getPoolKey(token0, token1, params.tickSpacing)
                );
                // we do not need to check veloPool is contract or not
                // because is case assume veloPool is not contract, it will revert
                (sqrtPriceX96, , , , , ) = IVelodromePool(veloPool).slot0();
            }
            recipient = params.recipient;
            tokenIn = params.tokenIn;
            tokenOut = params.tokenOut;
            amountIn = params.amountIn;
            minAmountOut = params.amountOutMinimum;
        }

        require(recipient == address(this), InvalidRecipient());
        OracleLib.OraclePrice memory oraclePrice = OracleLib.getPrice(token0, token1);
        _checkSwapSlippage(tokenIn, tokenOut, amountIn, minAmountOut, oraclePrice);
    }

    function _checkSwapSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        OracleLib.OraclePrice memory oraclePrice
    ) internal view {
        // calc expected amount out based on oracle price
        uint256 expectedAmountOut = tokenIn < tokenOut
            ? Math.mulDiv(
                amountIn,
                oraclePrice.price * 10 ** IERC20Metadata(tokenOut).decimals(),
                10 ** oraclePrice.decimals * 10 ** IERC20Metadata(tokenIn).decimals()
            )
            : Math.mulDiv(
                amountIn,
                10 ** oraclePrice.decimals * 10 ** IERC20Metadata(tokenOut).decimals(),
                oraclePrice.price * 10 ** IERC20Metadata(tokenIn).decimals()
            );

        // check slippage
        uint256 minAmountOutAccepted = Math.mulDiv(expectedAmountOut, _MAX_SLIPPAGE, _BPS);
        require(minAmountOut >= minAmountOutAccepted, SlippageExceeded());
    }

    // Derives pool address based on protocol variant using imported libraries
    function _getPoolPriceX96(
        address positionManager,
        Protocol protocol,
        address token0,
        address token1,
        int24 tickSpacing
    ) internal view returns (uint160 poolPriceX96) {
        if (protocol == Protocol.Velodrome) {
            address factory = IVelodromePositionManager(positionManager).factory();
            address poolAddress = PoolAddressVelodrome.computeAddress(
                factory,
                PoolAddressVelodrome.getPoolKey(token0, token1, tickSpacing)
            );
            // Get slot0 from pool
            (poolPriceX96, , , , , ) = IVelodromePool(poolAddress).slot0();
        } else if (protocol == Protocol.Thena) {
            address factory = IThenaPositionManager(positionManager).poolDeployer();
            address poolAddress = PoolAddressThena.computeAddress(factory, PoolAddressThena.getPoolKey(token0, token1));
            // Get slot0 from pool
            (poolPriceX96, , , , , , ) = IThenaPool(poolAddress).globalState();
        } else if (protocol == Protocol.Shadow) {
            address factory = IShadowPositionManager(positionManager).deployer();
            address poolAddress = PoolAddressShadow.computeAddress(
                factory,
                PoolAddressShadow.getPoolKey(token0, token1, tickSpacing)
            );
            // Get slot0 from pool
            (poolPriceX96, , , , , , ) = IShadowPool(poolAddress).slot0();
        } else {
            revert InvalidProtocol();
        }
    }

    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}
