// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { ValidatorTestBase } from 'test/Validators/ValidatorTestBase.sol';
import { IShadowPositionManager } from 'src/interfaces/IShadowPositionManager.sol';
import { IShadowRouter } from 'src/interfaces/IShadowRouter.sol';
import { IShadowPool } from 'src/interfaces/IShadowPool.sol';
import { IPositionManager } from 'src/interfaces/IPositionManager.sol'; // For CollectParams
import { IOracleAdapter } from 'src/interfaces/IOracleAdapter.sol';
import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { IValidator } from 'src/interfaces/IValidator.sol'; // Import IValidator for the struct
import { PoolAddress as PoolAddressShadow } from 'src/libraries/PoolAddressShadow.sol';
import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';

contract ShadowValidatorTests is ValidatorTestBase {
    // --- Test specific state variables ---
    address internal _tokenA;
    address internal _tokenB;
    address internal _mockPositionManager;
    address internal _mockRouter;
    address internal _mockPool;
    address internal _mockOracleAdapter;

    // Common parameters
    int24 internal _tickSpacing = 3000;
    uint8 internal _tokenA_Decimals = 18;
    uint8 internal _tokenB_Decimals = 6;
    uint8 internal _oracleDecimals = 8;

    // Use inherited setUp from ValidatorTestBase, add mock deployments and oracle registration
    function setUp() public override {
        super.setUp(); // Calls the base setup first

        // Assign fixed addresses for tokens, ensuring order
        _tokenA = address(0xA0A0A0);
        _tokenB = address(0xB0B0B0);
        if (_tokenA > _tokenB) {
            (_tokenA, _tokenB) = (_tokenB, _tokenA);
        }

        // Assign addresses for mock contracts
        _mockPositionManager = address(0xFACE1);
        _mockRouter = address(0xFACE2);
        _mockPool = address(0xFACE3);
        _mockOracleAdapter = address(0xFACE5);

        // Register the mock oracle adapter directly with the validator
        vm.prank(_governor);
        _validator.registerOracle(_tokenA, _tokenB, _mockOracleAdapter);

        // Set up common mock calls
        vm.mockCall(_tokenA, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_tokenA_Decimals));
        vm.mockCall(_tokenB, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_tokenB_Decimals));
        vm.mockCall(
            _mockOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.decimals.selector),
            abi.encode(_oracleDecimals)
        );
    }

    // --- Tests for Shadow Validations ---

    function testValidateExactInputSingleSuccess() public {
        // 1. Define parameters (use state variables where possible)
        uint256 amountIn = 1 * 10 ** uint256(_tokenA_Decimals); // 1 _tokenA
        uint160 limitSqrtPrice = 0;
        // int24 tickSpacing = 3000; // Use _tickSpacing
        uint256 maxSlippageBps = 100; // 1%
        // uint8 oracleDecimals = 8; // Use _oracleDecimals
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals)); // Price = 2

        uint256 expectedAmountOut = 2 * 10 ** uint256(_tokenB_Decimals);
        uint256 minAmountOutAccepted = (expectedAmountOut * (10000 - maxSlippageBps)) / 10000;
        uint256 amountOutMinimum = minAmountOutAccepted + 1;

        // 2. Setup Mocks (Only need latestAnswer here, others in setUp)
        vm.mockCall(
            _mockOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );

        // 3. Prepare Config Data
        bytes memory configData = abi.encode(maxSlippageBps);

        // 4. Prepare Params struct
        IShadowRouter.ExactInputSingleParams memory params = IShadowRouter.ExactInputSingleParams({
            tokenIn: _tokenA,
            tokenOut: _tokenB,
            tickSpacing: _tickSpacing,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: uint160(limitSqrtPrice)
        });

        // 5. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockRouter,
            externalSelector: IShadowRouter.exactInputSingle.selector,
            selfSelector: _validator.validateExactInputSingleShadow.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 6. Prepare full callData
        bytes memory callData = abi.encodeCall(IShadowRouter.exactInputSingle, (params));

        // 7. Call validate - should succeed
        _validator.validate(_mockRouter, callData);
        assertTrue(true); // Explicit success
    }

    function testValidateExactInputSingleRevertRecipient() public {
        // 1. Define parameters (most are arbitrary or from state)
        uint256 amountIn = 1 ether;
        uint160 limitSqrtPrice = 0;
        uint256 maxSlippageBps = 100;
        uint256 amountOutMinimum = 1;

        // 2. Prepare Config Data
        bytes memory configData = abi.encode(maxSlippageBps);

        // 3. Prepare Params struct with incorrect recipient
        IShadowRouter.ExactInputSingleParams memory params = IShadowRouter.ExactInputSingleParams({
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
            target: _mockRouter,
            externalSelector: IShadowRouter.exactInputSingle.selector,
            selfSelector: _validator.validateExactInputSingleShadow.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IShadowRouter.exactInputSingle, (params));

        // 6. Expect Revert and Call validate
        vm.expectRevert(IValidator.InvalidRecipient.selector);
        _validator.validate(_mockRouter, callData);
    }

    function testValidateExactInputSingleRevertSlippage() public {
        // 1. Define parameters (use state variables)
        uint256 amountIn = 1 * 10 ** uint256(_tokenA_Decimals); // 1 _tokenA
        uint160 limitSqrtPrice = 0;
        uint256 maxSlippageBps = 100; // 1%
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals)); // Price = 2

        uint256 expectedAmountOut = 2 * 10 ** uint256(_tokenB_Decimals);
        uint256 minAmountOutAccepted = (expectedAmountOut * (10000 - maxSlippageBps)) / 10000;
        uint256 amountOutMinimum_TooLow = minAmountOutAccepted == 0 ? 0 : minAmountOutAccepted - 1;
        require(amountOutMinimum_TooLow < expectedAmountOut, 'Test setup error');

        // 2. Setup Mocks (Only need latestAnswer here)
        vm.mockCall(
            _mockOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );

        // 3. Prepare Config Data
        bytes memory configData = abi.encode(maxSlippageBps);

        // 4. Prepare Params struct with low amountOutMinimum
        IShadowRouter.ExactInputSingleParams memory params = IShadowRouter.ExactInputSingleParams({
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
            target: _mockRouter,
            externalSelector: IShadowRouter.exactInputSingle.selector,
            selfSelector: _validator.validateExactInputSingleShadow.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 6. Prepare full callData
        bytes memory callData = abi.encodeCall(IShadowRouter.exactInputSingle, (params));

        // 7. Expect Revert and Call validate
        vm.expectRevert(IValidator.SlippageExceeded.selector);
        _validator.validate(_mockRouter, callData);
    }

    function testValidateMintShadowSuccess() public {
        // 1. Define parameters
        uint256 devPriceThresholdBps = 100; // 1%
        address deployerAddress = address(0xDe910777c7AB4958F2e8001550265453148174c9); // Corrected checksum

        // Oracle Price: 2 (tokenA per tokenB)
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));
        uint160 mockSqrtPriceX96 = 112300000000000000000000; // Approx 1.123e23

        // 2. Setup Mocks
        vm.mockCall(
            _mockOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        vm.mockCall(
            _mockPositionManager,
            abi.encodeWithSelector(IShadowPositionManager.deployer.selector),
            abi.encode(deployerAddress)
        );

        // Calculate expected pool address (Corrected types)
        PoolAddressShadow.PoolKey memory poolKey = PoolAddressShadow._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressShadow._computeAddress(deployerAddress, poolKey);

        // Mock pool slot0 call
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IShadowPool.slot0.selector),
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0, false)
        ); // Only sqrtPriceX96 matters here

        // 3. Prepare Config Data
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 4. Prepare Params struct
        IShadowPositionManager.MintParams memory params = IShadowPositionManager.MintParams({
            token0: _tokenA,
            token1: _tokenB,
            tickSpacing: _tickSpacing,
            tickLower: -_tickSpacing, // Example ticks
            tickUpper: _tickSpacing, // Example ticks
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this), // Valid recipient
            deadline: block.timestamp
        });

        // 5. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockPositionManager,
            externalSelector: IShadowPositionManager.mint.selector,
            selfSelector: _validator.validateMintShadow.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 6. Prepare full callData
        bytes memory callData = abi.encodeCall(IShadowPositionManager.mint, (params));

        // 7. Call validate - should succeed
        _validator.validate(_mockPositionManager, callData);
        assertTrue(true);
    }

    function testValidateMintShadowRevertRecipient() public {
        // 1. Define minimal parameters needed for recipient check
        uint256 devPriceThresholdBps = 100; // Not strictly needed, but required for registration

        // 2. Prepare Config Data
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 3. Prepare Params struct with incorrect recipient
        IShadowPositionManager.MintParams memory params = IShadowPositionManager.MintParams({
            token0: _tokenA,
            token1: _tokenB,
            tickSpacing: _tickSpacing,
            tickLower: -_tickSpacing,
            tickUpper: _tickSpacing,
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: _nonGovernor, // Incorrect recipient
            deadline: block.timestamp
        });

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockPositionManager,
            externalSelector: IShadowPositionManager.mint.selector,
            selfSelector: _validator.validateMintShadow.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IShadowPositionManager.mint, (params));

        // 6. Expect Revert and Call validate
        vm.expectRevert(IValidator.InvalidRecipient.selector);
        _validator.validate(_mockPositionManager, callData);
    }

    function testValidateMintShadowRevertDeviation() public {
        // 1. Define parameters
        uint256 devPriceThresholdBps = 100; // 1%
        address deployerAddress = address(0xDe910777c7AB4958F2e8001550265453148174c9);

        // Oracle Price: 2 (tokenA per tokenB) => Scaled price = 200,000,000
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));

        // Set pool price significantly off (e.g., > 1% deviation)
        // Price = 3 => Scaled price approx 300,000,000
        // sqrtP corresponding to this price ~ 1.37e23
        uint160 mockSqrtPriceX96_HighDeviation = 137000000000000000000000;

        // 2. Setup Mocks
        vm.mockCall(
            _mockOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        vm.mockCall(
            _mockPositionManager,
            abi.encodeWithSelector(IShadowPositionManager.deployer.selector),
            abi.encode(deployerAddress)
        );

        PoolAddressShadow.PoolKey memory poolKey = PoolAddressShadow._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressShadow._computeAddress(deployerAddress, poolKey);
        // Mock pool slot0 call with the high deviation price
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IShadowPool.slot0.selector),
            abi.encode(mockSqrtPriceX96_HighDeviation, 0, 0, 0, 0, 0, false)
        );

        // 3. Prepare Config Data
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 4. Prepare Params struct (with valid recipient)
        IShadowPositionManager.MintParams memory params = IShadowPositionManager.MintParams({
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
            deadline: block.timestamp
        });

        // 5. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockPositionManager,
            externalSelector: IShadowPositionManager.mint.selector,
            selfSelector: _validator.validateMintShadow.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 6. Prepare full callData
        bytes memory callData = abi.encodeCall(IShadowPositionManager.mint, (params));

        // 7. Expect Revert and Call validate
        vm.expectRevert(IValidator.PriceDeviationExceeded.selector);
        _validator.validate(_mockPositionManager, callData);
    }

    function testValidateIncreaseLiquiditySuccess() public {
        // 1. Define parameters
        uint256 tokenId = 1;
        uint256 devPriceThresholdBps = 100; // 1%
        address deployerAddress = address(0xDe910777c7AB4958F2e8001550265453148174c9);

        // Oracle Price: 2 (tokenA per tokenB)
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));
        // Pool price slightly off but within 1% deviation
        uint160 mockSqrtPriceX96 = 112300000000000000000000; // Approx 1.123e23

        // 2. Setup Mocks
        // Mock oracle price
        vm.mockCall(
            _mockOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Mock position data lookup -> returns our tokenA, tokenB, _tickSpacing
        vm.mockCall(
            _mockPositionManager,
            abi.encodeWithSelector(IShadowPositionManager.positions.selector, tokenId),
            abi.encode(_tokenA, _tokenB, _tickSpacing, 0, 0, 0, 0, 0, 0, 0) // Only first 3 return values needed
        );
        // Mock deployer lookup
        vm.mockCall(
            _mockPositionManager,
            abi.encodeWithSelector(IShadowPositionManager.deployer.selector),
            abi.encode(deployerAddress)
        );
        // Mock pool slot0 lookup
        PoolAddressShadow.PoolKey memory poolKey = PoolAddressShadow._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressShadow._computeAddress(deployerAddress, poolKey);
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IShadowPool.slot0.selector),
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0, false)
        );

        // 3. Prepare Config Data
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 4. Prepare Params struct
        IPositionManager.IncreaseLiquidityParams memory params = IPositionManager.IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        // 5. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockPositionManager,
            externalSelector: IPositionManager.increaseLiquidity.selector,
            selfSelector: _validator.validateIncreaseLiquidityShadow.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 6. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.increaseLiquidity, (params));

        // 7. Call validate - should succeed
        _validator.validate(_mockPositionManager, callData);
        assertTrue(true);
    }

    function testValidateIncreaseLiquidityRevertDeviation() public {
        // 1. Define parameters
        uint256 tokenId = 1;
        uint256 devPriceThresholdBps = 100; // 1%
        address deployerAddress = address(0xDe910777c7AB4958F2e8001550265453148174c9);

        // Oracle Price: 2
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));
        // Pool price far off (> 1% deviation)
        uint160 mockSqrtPriceX96_HighDeviation = 137000000000000000000000; // Approx 1.37e23 (Price ~3)

        // 2. Setup Mocks
        vm.mockCall(
            _mockOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        vm.mockCall(
            _mockPositionManager,
            abi.encodeWithSelector(IShadowPositionManager.positions.selector, tokenId),
            abi.encode(_tokenA, _tokenB, _tickSpacing, 0, 0, 0, 0, 0, 0, 0)
        );
        vm.mockCall(
            _mockPositionManager,
            abi.encodeWithSelector(IShadowPositionManager.deployer.selector),
            abi.encode(deployerAddress)
        );

        PoolAddressShadow.PoolKey memory poolKey = PoolAddressShadow._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressShadow._computeAddress(deployerAddress, poolKey);
        // Mock pool slot0 call with the high deviation price
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IShadowPool.slot0.selector),
            abi.encode(mockSqrtPriceX96_HighDeviation, 0, 0, 0, 0, 0, false)
        );

        // 3. Prepare Config Data
        bytes memory configData = abi.encode(devPriceThresholdBps);

        // 4. Prepare Params struct
        IPositionManager.IncreaseLiquidityParams memory params = IPositionManager.IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: 1 ether,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        // 5. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockPositionManager,
            externalSelector: IPositionManager.increaseLiquidity.selector,
            selfSelector: _validator.validateIncreaseLiquidityShadow.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 6. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.increaseLiquidity, (params));

        // 7. Expect Revert and Call validate
        vm.expectRevert(IValidator.PriceDeviationExceeded.selector);
        _validator.validate(_mockPositionManager, callData);
    }

    function testValidateDecreaseLiquidityShadowSuccess() public {
        // 1. Define parameters
        uint256 tokenId = 1;
        // Config data is not used by validateDecreaseLiquidityShadow, but needed for registration
        bytes memory configData = abi.encode(uint256(0)); // Dummy config data

        // 2. Prepare Params struct (amounts don't matter for this validation)
        IPositionManager.DecreaseLiquidityParams memory params = IPositionManager.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: 100, // Arbitrary non-zero value
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        // --- Mock the positions call needed by _validatePoolPriceFromTokenIdShadow ---
        vm.mockCall(
            _mockPositionManager,
            abi.encodeWithSelector(IShadowPositionManager.positions.selector, tokenId),
            abi.encode(_tokenA, _tokenB, _tickSpacing, 0, 0, 0, 0, 0, 0, 0) // Only first 3 return values needed
        );
        // We also need the mocks required by the nested _validatePoolPriceShadow call
        address deployerAddress = address(0xDe910777c7AB4958F2e8001550265453148174c9);
        vm.mockCall(
            _mockPositionManager,
            abi.encodeWithSelector(IShadowPositionManager.deployer.selector),
            abi.encode(deployerAddress)
        );
        PoolAddressShadow.PoolKey memory poolKey = PoolAddressShadow._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressShadow._computeAddress(deployerAddress, poolKey);
        uint160 mockSqrtPriceX96 = 1; // Dummy value, price check is skipped if devPriceThresholdBps=0
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IShadowPool.slot0.selector),
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0, false)
        );
        // We don't need to mock the oracle price because devPriceThresholdBps is 0, skipping the check
        // --- Correction: We DO need to mock oracle price + decimals, even if threshold is 0 ---
        uint256 oraclePriceValue = 1; // Dummy value, actual value doesn't matter for threshold=0
        vm.mockCall(
            _mockOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Ensure token decimals are mocked (they are already in global setUp, but explicit check is good)
        // vm.mockCall(_tokenA, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_tokenA_Decimals));
        // vm.mockCall(_tokenB, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_tokenB_Decimals));
        // ----------------------------------------------------------------------------------------

        // 3. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockPositionManager,
            externalSelector: IPositionManager.decreaseLiquidity.selector, // Use IPositionManager selector
            selfSelector: _validator.validateDecreaseLiquidityShadow.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 4. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.decreaseLiquidity, (params));

        // 5. Call validate - should succeed as there are no revert checks in this validation function
        _validator.validate(_mockPositionManager, callData);
        assertTrue(true); // Explicit success
    }

    // --- Tests for validateCollectShadow ---

    function testValidateCollectShadowSuccess() public {
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

        // 3. Mocks needed for _validatePoolPriceFromTokenIdShadow (even if skipped by threshold = 0)
        // Mock positions call
        vm.mockCall(
            _mockPositionManager,
            abi.encodeWithSelector(IShadowPositionManager.positions.selector, tokenId),
            abi.encode(_tokenA, _tokenB, _tickSpacing, 0, 0, 0, 0, 0, 0, 0)
        );
        // Mocks for nested _validatePoolPriceShadow -> _getPoolPriceX96Shadow
        address deployerAddress = address(0xDe910777c7AB4958F2e8001550265453148174c9);
        vm.mockCall(
            _mockPositionManager,
            abi.encodeWithSelector(IShadowPositionManager.deployer.selector),
            abi.encode(deployerAddress)
        );
        PoolAddressShadow.PoolKey memory poolKey = PoolAddressShadow._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressShadow._computeAddress(deployerAddress, poolKey);
        uint160 mockSqrtPriceX96 = 1; // Dummy value
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IShadowPool.slot0.selector),
            abi.encode(mockSqrtPriceX96, 0, 0, 0, 0, 0, false)
        );
        // Mocks for _checkPriceDeviation (needed even if skipped)
        uint256 oraclePriceValue = 1; // Dummy value
        vm.mockCall(
            _mockOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockPositionManager,
            externalSelector: IPositionManager.collect.selector,
            selfSelector: _validator.validateCollectShadow.selector,
            configData: configData
        });
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = registration;

        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 5. Prepare full callData
        bytes memory callData = abi.encodeCall(IPositionManager.collect, (params));

        // 6. Call validate - should succeed
        _validator.validate(_mockPositionManager, callData);
        assertTrue(true); // Explicit success
    }

    function testValidateCollectShadowRevertRecipient() public {
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
            target: _mockPositionManager,
            externalSelector: IPositionManager.collect.selector,
            selfSelector: _validator.validateCollectShadow.selector,
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
        _validator.validate(_mockPositionManager, callData);
    }

    function testValidateCollectShadowRevertDeviation() public {
        // 1. Define parameters
        uint256 tokenId = 1;
        uint256 devPriceThresholdBps = 100; // 1% - Non-zero threshold
        bytes memory configData = abi.encode(devPriceThresholdBps);
        address deployerAddress = address(0xDe910777c7AB4958F2e8001550265453148174c9);

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
            _mockPositionManager,
            abi.encodeWithSelector(IShadowPositionManager.positions.selector, tokenId),
            abi.encode(_tokenA, _tokenB, _tickSpacing, 0, 0, 0, 0, 0, 0, 0)
        );
        // Mock deployer
        vm.mockCall(
            _mockPositionManager,
            abi.encodeWithSelector(IShadowPositionManager.deployer.selector),
            abi.encode(deployerAddress)
        );
        // Mock pool slot0 with high deviation price
        PoolAddressShadow.PoolKey memory poolKey = PoolAddressShadow._getPoolKey(_tokenA, _tokenB, _tickSpacing);
        address expectedPoolAddress = PoolAddressShadow._computeAddress(deployerAddress, poolKey);
        uint160 mockSqrtPriceX96_HighDeviation = 137000000000000000000000; // Price ~3
        vm.mockCall(
            expectedPoolAddress,
            abi.encodeWithSelector(IShadowPool.slot0.selector),
            abi.encode(mockSqrtPriceX96_HighDeviation, 0, 0, 0, 0, 0, false)
        );
        // Mock oracle price (Price = 2)
        uint256 oraclePriceValue = 2 * (10 ** uint256(_oracleDecimals));
        vm.mockCall(
            _mockOracleAdapter,
            abi.encodeWithSelector(IOracleAdapter.latestAnswer.selector),
            abi.encode(int256(oraclePriceValue))
        );
        // Decimals are mocked in setUp

        // 4. Register the validation rule
        IValidator.ValidationRegistration memory registration = IValidator.ValidationRegistration({
            target: _mockPositionManager,
            externalSelector: IPositionManager.collect.selector,
            selfSelector: _validator.validateCollectShadow.selector,
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
        _validator.validate(_mockPositionManager, callData);
    }
}
