// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console } from 'forge-std/Script.sol';
import { IValidator } from 'src/interfaces/IValidator.sol';
import { Validator } from 'src/Validator.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IERC20Validator } from 'src/interfaces/IERC20Validator.sol';
import { IPositionManager } from 'src/interfaces/IPositionManager.sol';
import { IThenaRouter } from 'src/interfaces/IThenaRouter.sol';
import { IThenaPositionManager } from 'src/interfaces/IThenaPositionManager.sol';
import { IShadowRouter } from 'src/interfaces/IShadowRouter.sol';
import { IShadowPositionManager } from 'src/interfaces/IShadowPositionManager.sol';
import { IVelodromeRouter } from 'src/interfaces/IVelodromeRouter.sol';
import { IVelodromePositionManager } from 'src/interfaces/IVelodromePositionManager.sol';

contract RegisterValidationScript is Script {
    // --- Configuration ---
    // !!! Replace with actual deployed Validator address (likely the proxy) !!!
    address constant VALIDATOR_ADDRESS = address(0x01); // Placeholder

    // !!! Replace or fetch addresses for specific targets !!!
    // Placeholder Addresses:
    address constant MOCK_ERC20_TOKEN = address(0x10); // Target for transfer/approve
    address constant THENA_ROUTER = address(0x20);
    address constant THENA_POS_MAN = address(0x21);
    address constant SHADOW_ROUTER = address(0x30);
    address constant SHADOW_POS_MAN = address(0x31);
    address constant VELO_ROUTER = address(0x40);
    address constant VELO_POS_MAN = address(0x41);

    // Example Config Values:
    uint256 constant DEFAULT_MAX_SLIPPAGE_BPS = 100; // 1%
    uint256 constant DEFAULT_PRICE_DEV_BPS = 500; // 5%

    function run() external {
        // Define the total number of registrations
        uint256 numRegistrations = 17;
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](
            numRegistrations
        );
        uint256 regIndex = 0;

        // --- Get Validator Instance ---
        // Note: Make sure VALIDATOR_ADDRESS is the address of the *proxy* if using one
        Validator validator = Validator(payable(VALIDATOR_ADDRESS));

        // --- Define Registrations ---

        // == ERC20 Validations (2) ==
        // 1. transfer (allow any amount, any recipient)
        address[] memory allowedRecipients = new address[](0);
        bytes memory erc20TransferConfig = abi.encode(
            IERC20Validator.ERC20TransferConfig({ maxAmount: type(uint256).max, allowedRecipients: allowedRecipients })
        );
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: MOCK_ERC20_TOKEN,
            externalSelector: IERC20.transfer.selector,
            selfSelector: validator.validateERC20Transfer.selector,
            configData: erc20TransferConfig
        });

        // 2. approve (allow any amount, any spender)
        address[] memory allowedSpenders = new address[](0);
        bytes memory erc20ApproveConfig = abi.encode(
            IERC20Validator.ERC20AllowanceConfig({ maxAmount: type(uint256).max, allowedSpenders: allowedSpenders })
        );
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: MOCK_ERC20_TOKEN,
            externalSelector: IERC20.approve.selector,
            selfSelector: validator.validateERC20Allowance.selector,
            configData: erc20ApproveConfig
        });

        // == Thena Validations (5) ==
        bytes memory thenaPriceDevConfig = abi.encode(DEFAULT_PRICE_DEV_BPS);
        bytes memory thenaSwapConfig = abi.encode(DEFAULT_MAX_SLIPPAGE_BPS);
        // 3. mint
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: THENA_POS_MAN,
            externalSelector: IThenaPositionManager.mint.selector,
            selfSelector: validator.validateMintThena.selector,
            configData: thenaPriceDevConfig
        });
        // 4. exactInputSingle
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: THENA_ROUTER,
            externalSelector: IThenaRouter.exactInputSingle.selector,
            selfSelector: validator.validateExactInputSingleThena.selector,
            configData: thenaSwapConfig
        });
        // 5. increaseLiquidity
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: THENA_POS_MAN,
            externalSelector: IPositionManager.increaseLiquidity.selector,
            selfSelector: validator.validateIncreaseLiquidityThena.selector,
            configData: thenaPriceDevConfig
        });
        // 6. decreaseLiquidity
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: THENA_POS_MAN,
            externalSelector: IPositionManager.decreaseLiquidity.selector,
            selfSelector: validator.validateDecreaseLiquidityThena.selector,
            configData: thenaPriceDevConfig
        });
        // 7. collect
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: THENA_POS_MAN,
            externalSelector: IPositionManager.collect.selector,
            selfSelector: validator.validateCollectThena.selector,
            configData: thenaPriceDevConfig
        });

        // == Shadow Validations (5) ==
        bytes memory shadowPriceDevConfig = abi.encode(DEFAULT_PRICE_DEV_BPS);
        bytes memory shadowSwapConfig = abi.encode(DEFAULT_MAX_SLIPPAGE_BPS);
        // 8. mint
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: SHADOW_POS_MAN,
            externalSelector: IShadowPositionManager.mint.selector,
            selfSelector: validator.validateMintShadow.selector,
            configData: shadowPriceDevConfig
        });
        // 9. exactInputSingle
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: SHADOW_ROUTER,
            externalSelector: IShadowRouter.exactInputSingle.selector,
            selfSelector: validator.validateExactInputSingleShadow.selector,
            configData: shadowSwapConfig
        });
        // 10. increaseLiquidity
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: SHADOW_POS_MAN,
            externalSelector: IPositionManager.increaseLiquidity.selector,
            selfSelector: validator.validateIncreaseLiquidityShadow.selector,
            configData: shadowPriceDevConfig
        });
        // 11. decreaseLiquidity
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: SHADOW_POS_MAN,
            externalSelector: IPositionManager.decreaseLiquidity.selector,
            selfSelector: validator.validateDecreaseLiquidityShadow.selector,
            configData: shadowPriceDevConfig
        });
        // 12. collect
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: SHADOW_POS_MAN,
            externalSelector: IPositionManager.collect.selector,
            selfSelector: validator.validateCollectShadow.selector,
            configData: shadowPriceDevConfig
        });

        // == Velodrome Validations (5) ==
        bytes memory veloPriceDevConfig = abi.encode(DEFAULT_PRICE_DEV_BPS);
        bytes memory veloSwapConfig = abi.encode(DEFAULT_MAX_SLIPPAGE_BPS);
        // 13. mint
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: VELO_POS_MAN,
            externalSelector: IVelodromePositionManager.mint.selector,
            selfSelector: validator.validateMintVelodrome.selector,
            configData: veloPriceDevConfig
        });
        // 14. exactInputSingle
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: VELO_ROUTER,
            externalSelector: IVelodromeRouter.exactInputSingle.selector,
            selfSelector: validator.validateExactInputSingleVelodrome.selector,
            configData: veloSwapConfig
        });
        // 15. increaseLiquidity
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: VELO_POS_MAN,
            externalSelector: IPositionManager.increaseLiquidity.selector,
            selfSelector: validator.validateIncreaseLiquidityVelodrome.selector,
            configData: veloPriceDevConfig
        });
        // 16. decreaseLiquidity
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: VELO_POS_MAN,
            externalSelector: IPositionManager.decreaseLiquidity.selector,
            selfSelector: validator.validateDecreaseLiquidityVelodrome.selector,
            configData: veloPriceDevConfig
        });
        // 17. collect
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: VELO_POS_MAN,
            externalSelector: IPositionManager.collect.selector,
            selfSelector: validator.validateCollectVelodrome.selector,
            configData: veloPriceDevConfig
        });

        // --- Execute Registration ---
        require(VALIDATOR_ADDRESS != address(0), 'Validator address not set!');
        require(regIndex == registrations.length, 'Incorrect registration count');

        console.log('Preparing to register %d validations on Validator: %s', registrations.length, VALIDATOR_ADDRESS);

        vm.startBroadcast();
        validator.registerValidations(registrations);
        vm.stopBroadcast();

        console.log('Validations registered successfully on Validator:', VALIDATOR_ADDRESS);
    }
}
