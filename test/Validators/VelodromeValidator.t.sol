// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { ValidatorTestBase } from 'test/Validators/ValidatorTestBase.sol';
import { IVelodromePositionManager } from 'src/interfaces/IVelodromePositionManager.sol';
import { IVelodromeRouter } from 'src/interfaces/IVelodromeRouter.sol';
import { IVelodromePool } from 'src/interfaces/IVelodromePool.sol';
import { IVelodromeFactory } from 'src/interfaces/IVelodromeFactory.sol';
import { IPositionManager } from 'src/interfaces/IPositionManager.sol'; // For shared structs like CollectParams
import { IOracleAdapter } from 'src/interfaces/IOracleAdapter.sol';
import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { IValidator } from 'src/interfaces/IValidator.sol'; // Import IValidator for the struct/errors
import { PoolAddress as PoolAddressVelodrome } from 'src/libraries/PoolAddressVelodrome.sol';
import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';

contract VelodromeValidatorTests is ValidatorTestBase {
    // --- Test specific state variables ---
    address internal _tokenA;
    address internal _tokenB;
    address internal _mockVeloPositionManager;
    address internal _mockVeloRouter;
    address internal _mockVeloFactory;
    address internal _mockVeloPool; // Will be calculated based on factory and key
    address internal _mockVeloOracleAdapter;

    // Common parameters
    int24 internal _tickSpacing = 60; // Example Velodrome tick spacing
    uint8 internal _tokenA_Decimals = 18;
    uint8 internal _tokenB_Decimals = 6;
    uint8 internal _oracleDecimals = 8;

    // Use inherited setUp from ValidatorTestBase, add Velodrome mock setup
    function setUp() public override {
        super.setUp(); // Calls the base setup first

        // Assign fixed addresses for tokens, ensuring order
        _tokenA = address(0xA0A0A0);
        _tokenB = address(0xB0B0B0);
        if (_tokenA > _tokenB) {
            (_tokenA, _tokenB) = (_tokenB, _tokenA);
        }

        // Assign addresses for mock contracts
        _mockVeloPositionManager = address(0xFACE1);
        _mockVeloRouter = address(0xFACE2);
        _mockVeloFactory = address(0xFACE3); // Mock factory needed for pool address calc
        _mockVeloOracleAdapter = address(0xFACE5);

        // Register the mock oracle adapter directly with the validator
        vm.prank(_governor);
        _validator.registerOracle(_tokenA, _tokenB, _mockVeloOracleAdapter);

        // Set up common mock calls needed by many tests
        vm.mockCall(_tokenA, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_tokenA_Decimals));
        vm.mockCall(_tokenB, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_tokenB_Decimals));
        vm.mockCall(
            _mockVeloOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.decimals.selector),
            abi.encode(_oracleDecimals)
        );
        // Mock the factory lookup needed by _getPoolPriceX96Velodrome
        vm.mockCall(
            _mockVeloPositionManager,
            abi.encodeWithSelector(IVelodromePositionManager.factory.selector),
            abi.encode(_mockVeloFactory)
        );
        // Mock the pool implementation lookup needed by PoolAddressVelodrome._computeAddress
        vm.mockCall(
            _mockVeloFactory,
            abi.encodeWithSelector(IVelodromeFactory.poolImplementation.selector),
            abi.encode(address(0xBEAC01)) // Return a dummy beacon address
        );
    }

    // --- Tests for Velodrome Validations ---

    // --- Tests for validateExactInputSingleVelodrome ---

    function testValidateExactInputSingleVeloSuccess() public {
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
            _mockVeloOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 3. Prepare Config Data
        bytes memory configData = abi.encode(maxSlippageBps);

        // 4. Prepare Params struct (using IVelodromeRouter struct)
        IVelodromeRouter.ExactInputSingleParams memory params = IVelodromeRouter.ExactInputSingleParams({
            tokenIn: _tokenA,
            tokenOut: _tokenB,
            tickSpacing: _tickSpacing,
            recipient: address(this), // Use valid recipient
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum, // Use valid minimum amount
            sqrtPriceLimitX96: uint160(limitSqrtPrice)
        });

        // 5. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockVeloRouter,
            externalSelector: IVelodromeRouter.exactInputSingle.selector,
            selfSelector: _validator.validateExactInputSingleVelodrome.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 6. Prepare full callData
        bytes memory callData = abi.encodeCall(IVelodromeRouter.exactInputSingle, (params));

        // 7. Call validate - should succeed
        _validator.validate(_mockVeloRouter, callData);
        assertTrue(true); // Explicit success
    }

    function testValidateExactInputSingleVeloRevertRecipient() public {
        // 1. Define parameters (most are arbitrary or from state for recipient check)
        uint256 amountIn = 1 ether;
        uint160 limitSqrtPrice = 0;
        uint256 maxSlippageBps = 100;
        uint256 amountOutMinimum = 1;

        // 2. Prepare Config Data
        bytes memory configData = abi.encode(maxSlippageBps);

        // 3. Prepare Params struct with incorrect recipient
        IVelodromeRouter.ExactInputSingleParams memory params = IVelodromeRouter.ExactInputSingleParams({
            tokenIn: _tokenA,
            tokenOut: _tokenB,
            tickSpacing: _tickSpacing,
            recipient: _nonGovernor, // Use incorrect recipient
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: uint160(limitSqrtPrice)
        });

        // 4. Register the validation rule (no mocks needed for this path)
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockVeloRouter,
            externalSelector: IVelodromeRouter.exactInputSingle.selector,
            selfSelector: _validator.validateExactInputSingleVelodrome.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IVelodromeRouter.exactInputSingle, (params));

        // 6. Expect Revert and Call validate
        vm.expectRevert(IValidator.InvalidRecipient.selector);
        _validator.validate(_mockVeloRouter, callData);
    }

    function testValidateExactInputSingleVeloRevertSlippage() public {
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
            _mockVeloOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 3. Prepare Config Data
        bytes memory configData = abi.encode(maxSlippageBps);

        // 4. Prepare Params struct with low amountOutMinimum
        IVelodromeRouter.ExactInputSingleParams memory params = IVelodromeRouter.ExactInputSingleParams({
            tokenIn: _tokenA,
            tokenOut: _tokenB,
            tickSpacing: _tickSpacing,
            recipient: address(this), // Recipient is valid
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum_TooLow, // Too low
            sqrtPriceLimitX96: uint160(limitSqrtPrice)
        });

        // 5. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockVeloRouter,
            externalSelector: IVelodromeRouter.exactInputSingle.selector,
            selfSelector: _validator.validateExactInputSingleVelodrome.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 6. Prepare full callData
        bytes memory callData = abi.encodeCall(IVelodromeRouter.exactInputSingle, (params));

        // 7. Expect Revert and Call validate
        vm.expectRevert(IValidator.SlippageExceeded.selector);
        _validator.validate(_mockVeloRouter, callData);
    }

    // --- Tests for validateMintVelodrome ---

    function testValidateMintVeloSuccess() public {
        // 1. Define parameters
        uint256 devPriceThresholdBps = 0; // Use 0 to skip deviation check
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 2. Prepare Params struct
        IVelodromePositionManager.MintParams memory params = IVelodromePositionManager.MintParams({
            token0: _tokenA,
            token1: _tokenB,
            tickSpacing: _tickSpacing,
            tickLower: -_tickSpacing,
            tickUpper: _tickSpacing,
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this), // Valid recipient
            deadline: block.timestamp,
            sqrtPriceX96: 0 // Add missing field
        });

        // 3. Mocks needed for price validation path (_validatePoolPriceVelodrome -> _checkPriceDeviation)
        // Factory mock is in setUp
        // Mock pool slot0
        PoolAddressVelodrome.PoolKey memory poolKey = PoolAddressVelodrome._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressVelodrome._computeAddress(_mockVeloFactory, poolKey);
        uint160 mockSqrtPriceX96 = 1; // Dummy value
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IVelodromePool.slot0.selector),
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0) // Velodrome slot0 has 6 return values
        );
        // Mock oracle latestAnswer (needed even if check skipped)
        uint256 oraclePriceValue = 1; // Dummy value
        vm.mockCall(
            _mockVeloOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockVeloPositionManager,
            externalSelector: IVelodromePositionManager.mint.selector,
            selfSelector: _validator.validateMintVelodrome.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IVelodromePositionManager.mint, (params));

        // 6. Call validate - should succeed
        _validator.validate(_mockVeloPositionManager, callData);
        assertTrue(true);
    }

    function testValidateMintVeloRevertRecipient() public {
        // 1. Define parameters
        uint256 devPriceThresholdBps = 0; // Not relevant
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 2. Prepare Params struct with invalid recipient
        IVelodromePositionManager.MintParams memory params = IVelodromePositionManager.MintParams({
            token0: _tokenA,
            token1: _tokenB,
            tickSpacing: _tickSpacing,
            tickLower: -_tickSpacing,
            tickUpper: _tickSpacing,
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: _nonGovernor, // Invalid recipient
            deadline: block.timestamp,
            sqrtPriceX96: 0 // Add missing field
        });

        // 3. No mocks needed for recipient check

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockVeloPositionManager,
            externalSelector: IVelodromePositionManager.mint.selector,
            selfSelector: _validator.validateMintVelodrome.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IVelodromePositionManager.mint, (params));

        // 6. Expect Revert and Call validate
        vm.expectRevert(IValidator.InvalidRecipient.selector);
        _validator.validate(_mockVeloPositionManager, callData);
    }

    function testValidateMintVeloRevertDeviation() public {
        // 1. Define parameters
        uint256 devPriceThresholdBps = 100; // 1% - Non-zero threshold
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 2. Prepare Params struct with valid recipient
        IVelodromePositionManager.MintParams memory params = IVelodromePositionManager.MintParams({
            token0: _tokenA,
            token1: _tokenB,
            tickSpacing: _tickSpacing,
            tickLower: -_tickSpacing,
            tickUpper: _tickSpacing,
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this), // Valid recipient
            deadline: block.timestamp,
            sqrtPriceX96: 0 // Add missing field
        });

        // 3. Setup Mocks for deviation check
        // Factory mock is in setUp
        // Mock pool slot0 with high deviation price
        PoolAddressVelodrome.PoolKey memory poolKey = PoolAddressVelodrome._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressVelodrome._computeAddress(_mockVeloFactory, poolKey);
        uint160 mockSqrtPriceX96_HighDeviation = 137000000000000000000000; // Price ~3
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IVelodromePool.slot0.selector),
            abi.encode(mockSqrtPriceX96_HighDeviation, 0, 0, 0, 0, 0)
        );
        // Mock oracle price (Price = 2)
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));
        vm.mockCall(
            _mockVeloOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockVeloPositionManager,
            externalSelector: IVelodromePositionManager.mint.selector,
            selfSelector: _validator.validateMintVelodrome.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IVelodromePositionManager.mint, (params));

        // 6. Expect Revert and Call validate
        vm.expectRevert(IValidator.PriceDeviationExceeded.selector);
        _validator.validate(_mockVeloPositionManager, callData);
    }

    // --- Tests for validateIncreaseLiquidityVelodrome ---

    function testValidateIncreaseLiquidityVeloSuccess() public {
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

        // 3. Mocks needed for _validatePoolPriceFromTokenIdVelodrome -> _validatePoolPriceVelodrome -> _checkPriceDeviation
        // Mock positions call to get token details
        vm.mockCall(
            _mockVeloPositionManager,
            abi.encodeWithSelector(IVelodromePositionManager.positions.selector, tokenId),
            // Return mock data including tokenA, tokenB, tickSpacing (first 5 values relevant here based on _getPositionVelodrome)
            abi.encode(0, address(0), _tokenA, _tokenB, _tickSpacing, 0, 0, 0, 0, 0, 0, 0)
        );
        // Factory mock is in setUp
        // Mock pool slot0
        PoolAddressVelodrome.PoolKey memory poolKey = PoolAddressVelodrome._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressVelodrome._computeAddress(_mockVeloFactory, poolKey);
        uint160 mockSqrtPriceX96 = 1; // Dummy value
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IVelodromePool.slot0.selector),
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0)
        );
        // Mock oracle latestAnswer (needed even if check skipped)
        uint256 oraclePriceValue = 1; // Dummy value
        vm.mockCall(
            _mockVeloOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockVeloPositionManager,
            externalSelector: IPositionManager.increaseLiquidity.selector, // Using generic IPositionManager selector
            selfSelector: _validator.validateIncreaseLiquidityVelodrome.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.increaseLiquidity, (params));

        // 6. Call validate - should succeed
        _validator.validate(_mockVeloPositionManager, callData);
        assertTrue(true);
    }

    function testValidateIncreaseLiquidityVeloRevertDeviation() public {
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
            _mockVeloPositionManager,
            abi.encodeWithSelector(IVelodromePositionManager.positions.selector, tokenId),
            abi.encode(0, address(0), _tokenA, _tokenB, _tickSpacing, 0, 0, 0, 0, 0, 0, 0)
        );
        // Factory mock is in setUp
        // Mock pool slot0 with high deviation price
        PoolAddressVelodrome.PoolKey memory poolKey = PoolAddressVelodrome._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressVelodrome._computeAddress(_mockVeloFactory, poolKey);
        uint160 mockSqrtPriceX96_HighDeviation = 137000000000000000000000; // Price ~3
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IVelodromePool.slot0.selector),
            abi.encode(mockSqrtPriceX96_HighDeviation, 0, 0, 0, 0, 0)
        );
        // Mock oracle price (Price = 2)
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));
        vm.mockCall(
            _mockVeloOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockVeloPositionManager,
            externalSelector: IPositionManager.increaseLiquidity.selector,
            selfSelector: _validator.validateIncreaseLiquidityVelodrome.selector,
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
        _validator.validate(_mockVeloPositionManager, callData);
    }

    // --- Tests for validateDecreaseLiquidityVelodrome ---

    function testValidateDecreaseLiquidityVeloSuccess() public {
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

        // 3. Mocks needed for _validatePoolPriceFromTokenIdVelodrome -> ... -> _checkPriceDeviation
        // Mock positions call
        vm.mockCall(
            _mockVeloPositionManager,
            abi.encodeWithSelector(IVelodromePositionManager.positions.selector, tokenId),
            abi.encode(0, address(0), _tokenA, _tokenB, _tickSpacing, 0, 0, 0, 0, 0, 0, 0)
        );
        // Factory mock is in setUp
        // Mock pool slot0
        PoolAddressVelodrome.PoolKey memory poolKey = PoolAddressVelodrome._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressVelodrome._computeAddress(_mockVeloFactory, poolKey);
        uint160 mockSqrtPriceX96 = 1; // Dummy value
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IVelodromePool.slot0.selector),
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0)
        );
        // Mock oracle latestAnswer (needed even if check skipped)
        uint256 oraclePriceValue = 1; // Dummy value
        vm.mockCall(
            _mockVeloOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockVeloPositionManager,
            externalSelector: IPositionManager.decreaseLiquidity.selector, // Using generic IPositionManager selector
            selfSelector: _validator.validateDecreaseLiquidityVelodrome.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.decreaseLiquidity, (params));

        // 6. Call validate - should succeed
        _validator.validate(_mockVeloPositionManager, callData);
        assertTrue(true);
    }

    function testValidateDecreaseLiquidityVeloRevertDeviation() public {
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
            _mockVeloPositionManager,
            abi.encodeWithSelector(IVelodromePositionManager.positions.selector, tokenId),
            abi.encode(0, address(0), _tokenA, _tokenB, _tickSpacing, 0, 0, 0, 0, 0, 0, 0)
        );
        // Factory mock is in setUp
        // Mock pool slot0 with high deviation price
        PoolAddressVelodrome.PoolKey memory poolKey = PoolAddressVelodrome._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressVelodrome._computeAddress(_mockVeloFactory, poolKey);
        uint160 mockSqrtPriceX96_HighDeviation = 137000000000000000000000; // Price ~3
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IVelodromePool.slot0.selector),
            abi.encode(mockSqrtPriceX96_HighDeviation, 0, 0, 0, 0, 0)
        );
        // Mock oracle price (Price = 2)
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));
        vm.mockCall(
            _mockVeloOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockVeloPositionManager,
            externalSelector: IPositionManager.decreaseLiquidity.selector,
            selfSelector: _validator.validateDecreaseLiquidityVelodrome.selector,
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
        _validator.validate(_mockVeloPositionManager, callData);
    }

    // --- Tests for validateCollectVelodrome ---

    function testValidateCollectVeloSuccess() public {
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

        // 3. Mocks needed for _validatePoolPriceFromTokenIdVelodrome -> ... -> _checkPriceDeviation
        // Mock positions call
        vm.mockCall(
            _mockVeloPositionManager,
            abi.encodeWithSelector(IVelodromePositionManager.positions.selector, tokenId),
            abi.encode(0, address(0), _tokenA, _tokenB, _tickSpacing, 0, 0, 0, 0, 0, 0, 0)
        );
        // Factory mock is in setUp
        // Mock pool slot0
        PoolAddressVelodrome.PoolKey memory poolKey = PoolAddressVelodrome._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressVelodrome._computeAddress(_mockVeloFactory, poolKey);
        uint160 mockSqrtPriceX96 = 1; // Dummy value
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IVelodromePool.slot0.selector),
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0)
        );
        // Mock oracle latestAnswer (needed even if check skipped)
        uint256 oraclePriceValue = 1; // Dummy value
        vm.mockCall(
            _mockVeloOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockVeloPositionManager,
            externalSelector: IPositionManager.collect.selector, // Using generic IPositionManager selector
            selfSelector: _validator.validateCollectVelodrome.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.collect, (params));

        // 6. Call validate - should succeed
        _validator.validate(_mockVeloPositionManager, callData);
        assertTrue(true);
    }

    function testValidateCollectVeloRevertRecipient() public {
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
            target: _mockVeloPositionManager,
            externalSelector: IPositionManager.collect.selector,
            selfSelector: _validator.validateCollectVelodrome.selector,
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
        _validator.validate(_mockVeloPositionManager, callData);
    }

    function testValidateCollectVeloRevertDeviation() public {
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
            _mockVeloPositionManager,
            abi.encodeWithSelector(IVelodromePositionManager.positions.selector, tokenId),
            abi.encode(0, address(0), _tokenA, _tokenB, _tickSpacing, 0, 0, 0, 0, 0, 0, 0)
        );
        // Factory mock is in setUp
        // Mock pool slot0 with high deviation price
        PoolAddressVelodrome.PoolKey memory poolKey = PoolAddressVelodrome._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressVelodrome._computeAddress(_mockVeloFactory, poolKey);
        uint160 mockSqrtPriceX96_HighDeviation = 137000000000000000000000; // Price ~3
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IVelodromePool.slot0.selector),
            abi.encode(mockSqrtPriceX96_HighDeviation, 0, 0, 0, 0, 0)
        );
        // Mock oracle price (Price = 2)
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));
        vm.mockCall(
            _mockVeloOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockVeloPositionManager,
            externalSelector: IPositionManager.collect.selector,
            selfSelector: _validator.validateCollectVelodrome.selector,
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
        _validator.validate(_mockVeloPositionManager, callData);
    }
}
