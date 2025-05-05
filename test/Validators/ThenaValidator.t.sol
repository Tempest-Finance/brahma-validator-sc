// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { ValidatorTestBase } from 'test/Validators/ValidatorTestBase.sol';
import { IThenaPositionManager } from 'src/interfaces/IThenaPositionManager.sol';
import { IThenaRouter } from 'src/interfaces/IThenaRouter.sol';
import { IThenaPool } from 'src/interfaces/IThenaPool.sol';
import { IPositionManager } from 'src/interfaces/IPositionManager.sol'; // For shared structs like CollectParams
import { IOracleAdapter } from 'src/interfaces/IOracle.sol';
import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { IValidator } from 'src/interfaces/IValidator.sol'; // Import IValidator for the struct/errors
import { PoolAddress as PoolAddressThena } from 'src/libraries/PoolAddressThena.sol';
import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';

contract ThenaValidatorTests is ValidatorTestBase {
    // --- Test specific state variables ---
    address internal _tokenA;
    address internal _tokenB;
    address internal _mockThenaPositionManager;
    address internal _mockThenaRouter;
    address internal _mockThenaPoolDeployer;
    address internal _mockThenaOracleAdapter;

    // Common parameters (Thena doesn't use tickSpacing in pool key/price checks)
    uint8 internal _tokenA_Decimals = 18;
    uint8 internal _tokenB_Decimals = 6;
    uint8 internal _oracleDecimals = 8;

    // Use inherited setUp from ValidatorTestBase, add Thena mock setup
    function setUp() public override {
        super.setUp(); // Calls the base setup first

        // Assign fixed addresses for tokens, ensuring order
        _tokenA = address(0xA0A0A0);
        _tokenB = address(0xB0B0B0);
        if (_tokenA > _tokenB) {
            (_tokenA, _tokenB) = (_tokenB, _tokenA);
        }

        // Assign addresses for mock contracts
        _mockThenaPositionManager = address(0xFACE1);
        _mockThenaRouter = address(0xFACE2);
        _mockThenaPoolDeployer = address(0xFACE3); // Mock poolDeployer needed for pool address calc
        _mockThenaOracleAdapter = address(0xFACE5);

        // Register the mock oracle adapter directly with the validator
        vm.prank(_governor);
        _validator.registerOracle(_tokenA, _tokenB, _mockThenaOracleAdapter);

        // Set up common mock calls needed by many tests
        vm.mockCall(_tokenA, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_tokenA_Decimals));
        vm.mockCall(_tokenB, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_tokenB_Decimals));
        vm.mockCall(
            _mockThenaOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.decimals.selector),
            abi.encode(_oracleDecimals)
        );
        // Mock the poolDeployer lookup needed by _getPoolPriceX96Thena
        vm.mockCall(
            _mockThenaPositionManager,
            abi.encodeWithSelector(IThenaPositionManager.poolDeployer.selector),
            abi.encode(_mockThenaPoolDeployer)
        );
    }

    // --- Tests for Thena Validations ---

    // --- Tests for validateExactInputSingleThena ---

    function testValidateExactInputSingleThenaSuccess() public {
        // 1. Define parameters
        uint256 amountIn = 1 * 10 ** uint256(_tokenA_Decimals); // 1 _tokenA
        uint160 limitSqrtPrice = 0;
        uint256 maxSlippageBps = 100; // 1%
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals)); // Price = 2

        uint256 expectedAmountOut = 2 * 10 ** uint256(_tokenB_Decimals);
        uint256 minAmountOutAccepted = (expectedAmountOut * (10000 - maxSlippageBps)) / 10000;
        uint256 amountOutMinimum = minAmountOutAccepted + 1; // Ensure it's slightly higher than minimum

        // 2. Setup Mocks (Oracle price needed for slippage check)
        vm.mockCall(
            _mockThenaOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 3. Prepare Config Data
        bytes memory configData = abi.encode(maxSlippageBps);

        // 4. Prepare Params struct (using IThenaRouter struct - no tickSpacing)
        IThenaRouter.ExactInputSingleParams memory params = IThenaRouter.ExactInputSingleParams({
            tokenIn: _tokenA,
            tokenOut: _tokenB,
            recipient: address(this), // Use valid recipient
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum, // Use valid minimum amount
            limitSqrtPrice: uint160(limitSqrtPrice)
        });

        // 5. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaRouter,
            externalSelector: IThenaRouter.exactInputSingle.selector,
            selfSelector: _validator.validateExactInputSingleThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 6. Prepare full callData
        bytes memory callData = abi.encodeCall(IThenaRouter.exactInputSingle, (params));

        // 7. Call validate - should succeed
        _validator.validate(_mockThenaRouter, callData);
        assertTrue(true); // Explicit success
    }

    function testValidateExactInputSingleThenaRevertRecipient() public {
        // 1. Define parameters (most are arbitrary for recipient check)
        uint256 amountIn = 1 ether;
        uint160 limitSqrtPrice = 0;
        uint256 maxSlippageBps = 100;
        uint256 amountOutMinimum = 1;

        // 2. Prepare Config Data
        bytes memory configData = abi.encode(maxSlippageBps);

        // 3. Prepare Params struct with incorrect recipient
        IThenaRouter.ExactInputSingleParams memory params = IThenaRouter.ExactInputSingleParams({
            tokenIn: _tokenA,
            tokenOut: _tokenB,
            recipient: _nonGovernor, // Use incorrect recipient
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            limitSqrtPrice: uint160(limitSqrtPrice)
        });

        // 4. Register the validation rule (no mocks needed for this path)
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaRouter,
            externalSelector: IThenaRouter.exactInputSingle.selector,
            selfSelector: _validator.validateExactInputSingleThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IThenaRouter.exactInputSingle, (params));

        // 6. Expect Revert and Call validate
        vm.expectRevert(IValidator.InvalidRecipient.selector);
        _validator.validate(_mockThenaRouter, callData);
    }

    function testValidateExactInputSingleThenaRevertSlippage() public {
        // 1. Define parameters
        uint256 amountIn = 1 * 10 ** uint256(_tokenA_Decimals); // 1 _tokenA
        uint160 limitSqrtPrice = 0;
        uint256 maxSlippageBps = 100; // 1%
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals)); // Price = 2

        uint256 expectedAmountOut = 2 * 10 ** uint256(_tokenB_Decimals);
        uint256 minAmountOutAccepted = (expectedAmountOut * (10000 - maxSlippageBps)) / 10000;
        uint256 amountOutMinimum_TooLow = minAmountOutAccepted == 0 ? 0 : minAmountOutAccepted - 1;
        require(amountOutMinimum_TooLow < expectedAmountOut, 'Test setup error');

        // 2. Setup Mocks (Oracle price needed for slippage check)
        vm.mockCall(
            _mockThenaOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 3. Prepare Config Data
        bytes memory configData = abi.encode(maxSlippageBps);

        // 4. Prepare Params struct with low amountOutMinimum
        IThenaRouter.ExactInputSingleParams memory params = IThenaRouter.ExactInputSingleParams({
            tokenIn: _tokenA,
            tokenOut: _tokenB,
            recipient: address(this), // Recipient is valid
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum_TooLow, // Too low
            limitSqrtPrice: uint160(limitSqrtPrice)
        });

        // 5. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaRouter,
            externalSelector: IThenaRouter.exactInputSingle.selector,
            selfSelector: _validator.validateExactInputSingleThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 6. Prepare full callData
        bytes memory callData = abi.encodeCall(IThenaRouter.exactInputSingle, (params));

        // 7. Expect Revert and Call validate
        vm.expectRevert(IValidator.SlippageExceeded.selector);
        _validator.validate(_mockThenaRouter, callData);
    }

    // --- Tests for validateMintThena ---

    function testValidateMintThenaSuccess() public {
        // 1. Define parameters
        uint256 devPriceThresholdBps = 0; // Use 0 to skip deviation check
        bytes memory configData = abi.encode(devPriceThresholdBps);
        int24 tickLower = -60; // Example ticks
        int24 tickUpper = 60;

        // 2. Prepare Params struct (using IThenaPositionManager.MintParams)
        IThenaPositionManager.MintParams memory params = IThenaPositionManager.MintParams({
            token0: _tokenA,
            token1: _tokenB,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this), // Valid recipient
            deadline: block.timestamp
        });

        // 3. Mocks needed for price validation path (_validatePoolPriceThena -> _checkPriceDeviation)
        // poolDeployer mock is in setUp
        // Mock pool globalState
        PoolAddressThena.PoolKey memory poolKey = PoolAddressThena._getPoolKey(_tokenA, _tokenB);
        address expectedPoolAddress = PoolAddressThena._computeAddress(_mockThenaPoolDeployer, poolKey);
        uint160 mockSqrtPriceX96 = 1; // Dummy value
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IThenaPool.globalState.selector),
            // globalState returns 7 values, only sqrtPriceX96 matters for price check
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0, false)
        );
        // Mock oracle latestAnswer (needed even if check skipped)
        uint256 oraclePriceValue = 1; // Dummy value
        vm.mockCall(
            _mockThenaOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaPositionManager,
            externalSelector: IThenaPositionManager.mint.selector,
            selfSelector: _validator.validateMintThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IThenaPositionManager.mint, (params));

        // 6. Call validate - should succeed
        _validator.validate(_mockThenaPositionManager, callData);
        assertTrue(true);
    }

    function testValidateMintThenaRevertRecipient() public {
        // 1. Define parameters
        uint256 devPriceThresholdBps = 0; // Not relevant
        bytes memory configData = abi.encode(devPriceThresholdBps);
        int24 tickLower = -60;
        int24 tickUpper = 60;

        // 2. Prepare Params struct with invalid recipient
        IThenaPositionManager.MintParams memory params = IThenaPositionManager.MintParams({
            token0: _tokenA,
            token1: _tokenB,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: _nonGovernor, // Invalid recipient
            deadline: block.timestamp
        });

        // 3. No mocks needed for recipient check

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaPositionManager,
            externalSelector: IThenaPositionManager.mint.selector,
            selfSelector: _validator.validateMintThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IThenaPositionManager.mint, (params));

        // 6. Expect Revert and Call validate
        vm.expectRevert(IValidator.InvalidRecipient.selector);
        _validator.validate(_mockThenaPositionManager, callData);
    }

    function testValidateMintThenaRevertDeviation() public {
        // 1. Define parameters
        uint256 devPriceThresholdBps = 100; // 1% - Non-zero threshold
        bytes memory configData = abi.encode(devPriceThresholdBps);
        int24 tickLower = -60;
        int24 tickUpper = 60;

        // 2. Prepare Params struct with valid recipient
        IThenaPositionManager.MintParams memory params = IThenaPositionManager.MintParams({
            token0: _tokenA,
            token1: _tokenB,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this), // Valid recipient
            deadline: block.timestamp
        });

        // 3. Setup Mocks for deviation check
        // poolDeployer mock is in setUp
        // Mock pool globalState with high deviation price
        PoolAddressThena.PoolKey memory poolKey = PoolAddressThena._getPoolKey(_tokenA, _tokenB);
        address expectedPoolAddress = PoolAddressThena._computeAddress(_mockThenaPoolDeployer, poolKey);
        uint160 mockSqrtPriceX96_HighDeviation = 137000000000000000000000; // Price ~3
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IThenaPool.globalState.selector),
            abi.encode(mockSqrtPriceX96_HighDeviation, 0, 0, 0, 0, 0, false)
        );
        // Mock oracle price (Price = 2)
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));
        vm.mockCall(
            _mockThenaOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaPositionManager,
            externalSelector: IThenaPositionManager.mint.selector,
            selfSelector: _validator.validateMintThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IThenaPositionManager.mint, (params));

        // 6. Expect Revert and Call validate
        vm.expectRevert(IValidator.PriceDeviationExceeded.selector);
        _validator.validate(_mockThenaPositionManager, callData);
    }

    // --- Tests for validateIncreaseLiquidityThena ---

    function testValidateIncreaseLiquidityThenaSuccess() public {
        // 1. Define parameters
        uint256 tokenId = 1;
        uint256 devPriceThresholdBps = 0; // Use 0 to skip deviation check
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 2. Prepare Params struct
        IPositionManager.IncreaseLiquidityParams memory params = IPositionManager.IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        // 3. Mocks needed for _validatePoolPriceFromTokenIdThena -> ... -> _checkPriceDeviation
        // Mock positions call to get token details
        vm.mockCall(
            _mockThenaPositionManager,
            abi.encodeWithSelector(IThenaPositionManager.positions.selector, tokenId),
            // Return mock data including tokenA, tokenB (first 4 values relevant based on _getPositionThena)
            abi.encode(0, address(0), _tokenA, _tokenB, 0, 0, 0, 0, 0, 0, 0)
        );
        // poolDeployer mock is in setUp
        // Mock pool globalState
        PoolAddressThena.PoolKey memory poolKey = PoolAddressThena._getPoolKey(_tokenA, _tokenB);
        address expectedPoolAddress = PoolAddressThena._computeAddress(_mockThenaPoolDeployer, poolKey);
        uint160 mockSqrtPriceX96 = 1; // Dummy value
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IThenaPool.globalState.selector),
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0, false)
        );
        // Mock oracle latestAnswer (needed even if check skipped)
        uint256 oraclePriceValue = 1; // Dummy value
        vm.mockCall(
            _mockThenaOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaPositionManager,
            externalSelector: IPositionManager.increaseLiquidity.selector,
            selfSelector: _validator.validateIncreaseLiquidityThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.increaseLiquidity, (params));

        // 6. Call validate - should succeed
        _validator.validate(_mockThenaPositionManager, callData);
        assertTrue(true);
    }

    function testValidateIncreaseLiquidityThenaRevertDeviation() public {
        // 1. Define parameters
        uint256 tokenId = 1;
        uint256 devPriceThresholdBps = 100; // 1% - Non-zero threshold
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 2. Prepare Params struct
        IPositionManager.IncreaseLiquidityParams memory params = IPositionManager.IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        // 3. Setup Mocks for deviation check
        // Mock positions call
        vm.mockCall(
            _mockThenaPositionManager,
            abi.encodeWithSelector(IThenaPositionManager.positions.selector, tokenId),
            abi.encode(0, address(0), _tokenA, _tokenB, 0, 0, 0, 0, 0, 0, 0)
        );
        // poolDeployer mock is in setUp
        // Mock pool globalState with high deviation price
        PoolAddressThena.PoolKey memory poolKey = PoolAddressThena._getPoolKey(_tokenA, _tokenB);
        address expectedPoolAddress = PoolAddressThena._computeAddress(_mockThenaPoolDeployer, poolKey);
        uint160 mockSqrtPriceX96_HighDeviation = 137000000000000000000000; // Price ~3
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IThenaPool.globalState.selector),
            abi.encode(mockSqrtPriceX96_HighDeviation, 0, 0, 0, 0, 0, false)
        );
        // Mock oracle price (Price = 2)
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));
        vm.mockCall(
            _mockThenaOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaPositionManager,
            externalSelector: IPositionManager.increaseLiquidity.selector,
            selfSelector: _validator.validateIncreaseLiquidityThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.increaseLiquidity, (params));

        // 6. Expect Revert and Call validate
        vm.expectRevert(IValidator.PriceDeviationExceeded.selector);
        _validator.validate(_mockThenaPositionManager, callData);
    }

    // --- Tests for validateDecreaseLiquidityThena ---

    function testValidateDecreaseLiquidityThenaSuccess() public {
        // 1. Define parameters
        uint256 tokenId = 1;
        uint256 devPriceThresholdBps = 0; // Use 0 to skip deviation check
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 2. Prepare Params struct
        IPositionManager.DecreaseLiquidityParams memory params = IPositionManager.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: 100,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        // 3. Mocks needed for _validatePoolPriceFromTokenIdThena -> ... -> _checkPriceDeviation
        // Mock positions call
        vm.mockCall(
            _mockThenaPositionManager,
            abi.encodeWithSelector(IThenaPositionManager.positions.selector, tokenId),
            abi.encode(0, address(0), _tokenA, _tokenB, 0, 0, 0, 0, 0, 0, 0)
        );
        // poolDeployer mock is in setUp
        // Mock pool globalState
        PoolAddressThena.PoolKey memory poolKey = PoolAddressThena._getPoolKey(_tokenA, _tokenB);
        address expectedPoolAddress = PoolAddressThena._computeAddress(_mockThenaPoolDeployer, poolKey);
        uint160 mockSqrtPriceX96 = 1; // Dummy value
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IThenaPool.globalState.selector),
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0, false)
        );
        // Mock oracle latestAnswer (needed even if check skipped)
        uint256 oraclePriceValue = 1; // Dummy value
        vm.mockCall(
            _mockThenaOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaPositionManager,
            externalSelector: IPositionManager.decreaseLiquidity.selector,
            selfSelector: _validator.validateDecreaseLiquidityThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.decreaseLiquidity, (params));

        // 6. Call validate - should succeed
        _validator.validate(_mockThenaPositionManager, callData);
        assertTrue(true);
    }

    function testValidateDecreaseLiquidityThenaRevertDeviation() public {
        // 1. Define parameters
        uint256 tokenId = 1;
        uint256 devPriceThresholdBps = 100; // 1% - Non-zero threshold
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 2. Prepare Params struct
        IPositionManager.DecreaseLiquidityParams memory params = IPositionManager.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: 100,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        // 3. Setup Mocks for deviation check
        // Mock positions call
        vm.mockCall(
            _mockThenaPositionManager,
            abi.encodeWithSelector(IThenaPositionManager.positions.selector, tokenId),
            abi.encode(0, address(0), _tokenA, _tokenB, 0, 0, 0, 0, 0, 0, 0)
        );
        // poolDeployer mock is in setUp
        // Mock pool globalState with high deviation price
        PoolAddressThena.PoolKey memory poolKey = PoolAddressThena._getPoolKey(_tokenA, _tokenB);
        address expectedPoolAddress = PoolAddressThena._computeAddress(_mockThenaPoolDeployer, poolKey);
        uint160 mockSqrtPriceX96_HighDeviation = 137000000000000000000000; // Price ~3
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IThenaPool.globalState.selector),
            abi.encode(mockSqrtPriceX96_HighDeviation, 0, 0, 0, 0, 0, false)
        );
        // Mock oracle price (Price = 2)
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));
        vm.mockCall(
            _mockThenaOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaPositionManager,
            externalSelector: IPositionManager.decreaseLiquidity.selector,
            selfSelector: _validator.validateDecreaseLiquidityThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.decreaseLiquidity, (params));

        // 6. Expect Revert and Call validate
        vm.expectRevert(IValidator.PriceDeviationExceeded.selector);
        _validator.validate(_mockThenaPositionManager, callData);
    }

    // --- Tests for validateCollectThena ---

    function testValidateCollectThenaSuccess() public {
        // 1. Define parameters
        uint256 tokenId = 1;
        uint256 devPriceThresholdBps = 0; // Use 0 to skip deviation check
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 2. Prepare Params struct (using valid recipient)
        IPositionManager.CollectParams memory params = IPositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this), // Valid recipient
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        // 3. Mocks needed for _validatePoolPriceFromTokenIdThena -> ... -> _checkPriceDeviation
        // Mock positions call
        vm.mockCall(
            _mockThenaPositionManager,
            abi.encodeWithSelector(IThenaPositionManager.positions.selector, tokenId),
            abi.encode(0, address(0), _tokenA, _tokenB, 0, 0, 0, 0, 0, 0, 0)
        );
        // poolDeployer mock is in setUp
        // Mock pool globalState
        PoolAddressThena.PoolKey memory poolKey = PoolAddressThena._getPoolKey(_tokenA, _tokenB);
        address expectedPoolAddress = PoolAddressThena._computeAddress(_mockThenaPoolDeployer, poolKey);
        uint160 mockSqrtPriceX96 = 1; // Dummy value
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IThenaPool.globalState.selector),
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0, false)
        );
        // Mock oracle latestAnswer (needed even if check skipped)
        uint256 oraclePriceValue = 1; // Dummy value
        vm.mockCall(
            _mockThenaOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaPositionManager,
            externalSelector: IPositionManager.collect.selector, // Using generic IPositionManager selector
            selfSelector: _validator.validateCollectThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.collect, (params));

        // 6. Call validate - should succeed
        _validator.validate(_mockThenaPositionManager, callData);
        assertTrue(true);
    }

    function testValidateCollectThenaRevertRecipient() public {
        // 1. Define parameters
        uint256 tokenId = 1;
        uint256 devPriceThresholdBps = 0; // Not relevant for this check
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 2. Prepare Params struct (using invalid recipient)
        IPositionManager.CollectParams memory params = IPositionManager.CollectParams({
            tokenId: tokenId,
            recipient: _nonGovernor, // Invalid recipient
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        // 3. No mocks needed for recipient check path

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaPositionManager,
            externalSelector: IPositionManager.collect.selector,
            selfSelector: _validator.validateCollectThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.collect, (params));

        // 6. Expect Revert and Call validate
        vm.expectRevert(IValidator.InvalidRecipient.selector);
        _validator.validate(_mockThenaPositionManager, callData);
    }

    function testValidateCollectThenaRevertDeviation() public {
        // 1. Define parameters
        uint256 tokenId = 1;
        uint256 devPriceThresholdBps = 100; // 1% - Non-zero threshold
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 2. Prepare Params struct (using valid recipient)
        IPositionManager.CollectParams memory params = IPositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this), // Valid recipient
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        // 3. Setup Mocks for deviation check
        // Mock positions call
        vm.mockCall(
            _mockThenaPositionManager,
            abi.encodeWithSelector(IThenaPositionManager.positions.selector, tokenId),
            abi.encode(0, address(0), _tokenA, _tokenB, 0, 0, 0, 0, 0, 0, 0)
        );
        // poolDeployer mock is in setUp
        // Mock pool globalState with high deviation price
        PoolAddressThena.PoolKey memory poolKey = PoolAddressThena._getPoolKey(_tokenA, _tokenB);
        address expectedPoolAddress = PoolAddressThena._computeAddress(_mockThenaPoolDeployer, poolKey);
        uint160 mockSqrtPriceX96_HighDeviation = 137000000000000000000000; // Price ~3
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IThenaPool.globalState.selector),
            abi.encode(mockSqrtPriceX96_HighDeviation, 0, 0, 0, 0, 0, false)
        );
        // Mock oracle price (Price = 2)
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));
        vm.mockCall(
            _mockThenaOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockThenaPositionManager,
            externalSelector: IPositionManager.collect.selector,
            selfSelector: _validator.validateCollectThena.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.collect, (params));

        // 6. Expect Revert and Call validate
        vm.expectRevert(IValidator.PriceDeviationExceeded.selector);
        _validator.validate(_mockThenaPositionManager, callData);
    }

    // TODO: Add tests starting with validateExactInputSingleThena
}
