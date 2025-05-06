// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from 'forge-std/Script.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { Validator } from 'src/Validator.sol';
import { IValidator } from 'src/interfaces/IValidator.sol';
import { IERC20Validator } from 'src/interfaces/IERC20Validator.sol';
import { IPositionManager } from 'src/interfaces/IPositionManager.sol';
import { IThenaRouter } from 'src/interfaces/IThenaRouter.sol';
import { IThenaPositionManager } from 'src/interfaces/IThenaPositionManager.sol';
import { IShadowRouter } from 'src/interfaces/IShadowRouter.sol';
import { IShadowPositionManager } from 'src/interfaces/IShadowPositionManager.sol';
import { IVelodromeRouter } from 'src/interfaces/IVelodromeRouter.sol';
import { IVelodromeGauge } from 'src/interfaces/IVelodromeGauge.sol';
import { IVelodromePositionManager } from 'src/interfaces/IVelodromePositionManager.sol';

contract RegisterVeloValidationScript is Script {
    // --- Configuration ---
    address constant _VALIDATOR_ADDRESS = address(0xC5a5973BA7675b5Fa79162866e101817D83ce834); // Placeholder

    address constant _VELO_ROUTER = address(0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5);
    address constant _VELO_POS_MAN = address(0x827922686190790b37229fd06084350E74485b72);
    address constant _OPEN_OCEAN = address(0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5);

    // Example Config Values:
    uint256 constant _DEFAULT_MAX_SLIPPAGE_BPS = 200; // 2%
    uint256 constant _DEFAULT_PRICE_DEV_BPS = 200; // 2%

    // Token Addresses
    address constant _WETH = 0x4200000000000000000000000000000000000006; // WETH
    address constant _USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC
    address constant _cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf; // cbBTC
    address constant _USDp = 0xB79DD08EA68A908A97220C76d19A6aA9cBDE4376; // USD+
    address constant _VIRTUAL = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b; // VIRTUAL
    address constant _wstETH = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452; // wstETH
    address constant _USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2; // USDT
    address constant _BRETT = 0x532f27101965dd16442E59d40670FaF5eBB142E4; // BRETT

    address constant _AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631; // AERO
    address constant _FEE_RECIPIENT = 0x6f00B52f64A041E7623a9747EcBDA91d619E2Caa; // BRETT

    function run() external {
        // Define the total number of registrations
        uint256 numRegistrations = 36;
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](
            numRegistrations
        );
        uint256 regIndex = 0;

        // --- Get Validator Instance ---
        Validator validator = Validator(payable(_VALIDATOR_ADDRESS));

        // --- Define Registrations ---

        // == ERC20 Validations (2) ==

        // validate 7 tokens for allowance (0-7)
        address[] memory tokens = _getTokensForAllowance();
        for (uint256 i = 0; i < tokens.length; i++) {
            address[] memory allowedSpenders = new address[](2);
            allowedSpenders[0] = _VELO_ROUTER;
            allowedSpenders[1] = _VELO_POS_MAN;
            bytes memory erc20AllowanceConfig = abi.encode(
                IERC20Validator.ERC20AllowanceConfig({ maxAmount: type(uint256).max, allowedSpenders: allowedSpenders })
            );
            registrations[regIndex++] = IValidator.ValidationRegistration({
                target: tokens[i],
                externalSelector: IERC20.approve.selector,
                selfSelector: validator.validateERC20Allowance.selector,
                configData: erc20AllowanceConfig
            });
        }

        // == Velodrome Validations ==
        bytes memory veloPriceDevConfig = abi.encode(_DEFAULT_PRICE_DEV_BPS);
        bytes memory veloSwapConfig = abi.encode(_DEFAULT_MAX_SLIPPAGE_BPS);

        // 7.mint
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: _VELO_POS_MAN,
            externalSelector: IVelodromePositionManager.mint.selector,
            selfSelector: validator.validateMintVelodrome.selector,
            configData: veloPriceDevConfig
        });

        // 8. decreaseLiquidity
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: _VELO_POS_MAN,
            externalSelector: IPositionManager.decreaseLiquidity.selector,
            selfSelector: validator.validateDecreaseLiquidityVelodrome.selector,
            configData: veloPriceDevConfig
        });

        // 9. collect
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: _VELO_POS_MAN,
            externalSelector: IPositionManager.collect.selector,
            selfSelector: validator.validateCollectVelodrome.selector,
            configData: veloPriceDevConfig
        });

        // 10. burn
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: _VELO_POS_MAN,
            externalSelector: IPositionManager.burn.selector,
            selfSelector: validator.noValidate.selector,
            configData: veloPriceDevConfig
        });

        // 11. approve for gauges
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: _VELO_POS_MAN,
            externalSelector: IERC721.approve.selector,
            selfSelector: validator.validateERC721Allowance.selector,
            configData: abi.encode(_getGauges()) // allowed spenders are gauges
        });

        // 12. exactInputSingle
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: _VELO_ROUTER,
            externalSelector: IVelodromeRouter.exactInputSingle.selector,
            selfSelector: validator.validateExactInputSingleVelodrome.selector,
            configData: veloSwapConfig
        });

        // 13. approve AERO
        address[] memory allowedSpenders = new address[](3);
        allowedSpenders[0] = _VELO_ROUTER;
        allowedSpenders[1] = _VELO_POS_MAN;
        allowedSpenders[2] = _OPEN_OCEAN;
        bytes memory aeroAllowanceConfig = abi.encode(
            IERC20Validator.ERC20AllowanceConfig({ maxAmount: type(uint256).max, allowedSpenders: allowedSpenders })
        );
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: _AERO,
            externalSelector: IERC20.approve.selector,
            selfSelector: validator.validateERC20Allowance.selector,
            configData: aeroAllowanceConfig
        });

        // 14. transfer AERO
        address[] memory aeroRecipients = new address[](1);
        aeroRecipients[0] = _FEE_RECIPIENT;
        bytes memory aeroTransferConfig = abi.encode(
            IERC20Validator.ERC20TransferConfig({ allowedRecipients: aeroRecipients, maxAmount: type(uint256).max })
        );
        registrations[regIndex++] = IValidator.ValidationRegistration({
            target: _AERO,
            externalSelector: IERC20.transfer.selector,
            selfSelector: validator.validateERC20Transfer.selector,
            configData: aeroTransferConfig
        });

        address[] memory gauges = _getGauges();
        for (uint256 i = 0; i < gauges.length; i++) {
            registrations[regIndex++] = IValidator.ValidationRegistration({
                target: gauges[i],
                externalSelector: IVelodromeGauge.deposit.selector,
                selfSelector: validator.noValidate.selector,
                configData: ''
            });
            registrations[regIndex++] = IValidator.ValidationRegistration({
                target: gauges[i],
                externalSelector: IVelodromeGauge.withdraw.selector,
                selfSelector: validator.noValidate.selector,
                configData: ''
            });
        }

        // --- Execute Registration ---
        require(_VALIDATOR_ADDRESS != address(0), 'Validator address not set!');
        require(regIndex == registrations.length, 'Incorrect registration count');

        console.log('Preparing to register %d validations on Validator: %s', registrations.length, _VALIDATOR_ADDRESS);

        vm.startBroadcast();
        validator.registerValidations(registrations);
        vm.stopBroadcast();

        console.log('Validations registered successfully on Validator:', _VALIDATOR_ADDRESS);
    }

    function _getTokensForAllowance() internal pure returns (address[] memory) {
        address[] memory tokens = new address[](8);
        tokens[0] = _WETH;
        tokens[1] = _USDC;
        tokens[2] = _cbBTC;
        tokens[3] = _USDp;
        tokens[4] = _VIRTUAL;
        tokens[5] = _wstETH;
        tokens[6] = _USDT;
        tokens[7] = _BRETT;
        return tokens;
    }

    function _getGauges() internal pure returns (address[] memory gauges) {
        gauges = new address[](10);
        gauges[0] = 0xF33a96b5932D9E9B9A0eDA447AbD8C9d48d2e0c8;
        gauges[1] = 0x41b2126661C673C2beDd208cC72E85DC51a5320a;
        gauges[2] = 0x6399ed6725cC163D019aA64FF55b22149D7179A8;
        gauges[3] = 0xcC2714BF50F3c7174a868bec8f4D4d284A0b07cc;
        gauges[4] = 0xBDA319Bc7Cc8F0829df39eC0FFF5D1E061FFadf7;
        gauges[5] = 0xFd73Ab1100a60Ba64686ef9dcdE36d0209773f6a;
        gauges[6] = 0x2A1f7bf46bd975b5004b61c6040597E1B6117040;
        gauges[7] = 0x2c0CbF25Bb64687d11ea2E4a3dc893D56Ca39c10;
        gauges[8] = 0xeA22A3AAdA580bD75Fb6caC35034e09046cbFf72;
        gauges[9] = 0xdE8FF0D3e8ab225110B088a250b546015C567E27;
        return gauges;
    }
}
