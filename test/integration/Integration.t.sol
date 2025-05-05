// SPDX-License-Identifier: MIT

pragma solidity >=0.8.24;

import { Address } from 'openzeppelin-contracts/contracts/utils/Address.sol';
import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';
import { BridgeOracle } from 'src/BridgeOracle.sol';
import { Validator } from 'src/Validator.sol';
import { IERC20Validator } from 'src/interfaces/IERC20Validator.sol';
import { IVelodromeValidator } from 'src/interfaces/IVelodromeValidator.sol';
import { IVelodromePositionManager } from 'src/interfaces/IVelodromePositionManager.sol';
import { IValidator } from 'src/interfaces/IValidator.sol';
import { IPositionManager } from 'src/interfaces/IPositionManager.sol';
import { IVelodromeRouter } from 'src/interfaces/IVelodromeRouter.sol';
import { MultiSendCallOnly } from 'src/MultiSendCallOnly.sol';
import { IVelodromeGauge } from 'src/interfaces/IVelodromeGauge.sol';

interface ISafeWallet {
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    ) external returns (bool success, bytes memory returnData);
}

contract IntegrationTest is Test {
    using Address for address;

    address internal _executorPlugin = 0xb92929d03768a4F8D69552e15a8071EAf8E684ed;
    address internal _multiSendCallOnlyAddr = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;
    address internal _safeWallet = 0x150FC1542B18Fc2F30b383c9d13f71B0930F4255;
    address internal _token0 = 0x4200000000000000000000000000000000000006;
    address internal _token1 = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal _swapRouter = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;
    address internal _pool = 0xb2cc224c1c9feE385f8ad6a55b4d94E92359DC59;
    address internal _positionManager = 0x827922686190790b37229fd06084350E74485b72;

    address internal _ethOracle = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address internal _usdcOracle = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address internal _sequencerOracle = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    address internal _gauge = 0xF33a96b5932D9E9B9A0eDA447AbD8C9d48d2e0c8;
    address internal _feeToken = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address internal _feeRecipient = 0x6f00B52f64A041E7623a9747EcBDA91d619E2Caa;

    MultiSendCallOnly internal _multiSendCallOnly;
    BridgeOracle internal _bridgeOracle;
    Validator internal _validator;

    event ExecutionFromModuleSuccess(address indexed module);

    function _setUpContracts() internal {
        _bridgeOracle = new BridgeOracle(
            _ethOracle,
            _usdcOracle,
            _sequencerOracle,
            1 hours,
            1 days,
            1 hours,
            true,
            'ETH/USDC',
            address(this)
        );

        _validator = new Validator();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(_validator),
            address(this),
            abi.encodeWithSelector(Validator.initialize.selector, address(this))
        );
        _validator = Validator(address(proxy));
        _validator.registerOracle(_token0, _token1, address(_bridgeOracle));

        _multiSendCallOnly = new MultiSendCallOnly(address(_validator));
        vm.etch(_multiSendCallOnlyAddr, address(_multiSendCallOnly).code);

        // register validators
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](9);
        uint256 _registrationIndex = 0;
        // approve validation
        {
            address[] memory allowedSpenders = new address[](2);
            allowedSpenders[0] = _swapRouter;
            allowedSpenders[1] = _positionManager;
            bytes memory erc20ApproveConfig = abi.encode(
                IERC20Validator.ERC20AllowanceConfig({ maxAmount: type(uint256).max, allowedSpenders: allowedSpenders })
            );
            registrations[_registrationIndex++] = IValidator.ValidationRegistration({
                target: _token0,
                externalSelector: IERC20.approve.selector,
                selfSelector: IERC20Validator.validateERC20Allowance.selector,
                configData: erc20ApproveConfig
            });

            registrations[_registrationIndex++] = IValidator.ValidationRegistration({
                target: _token1,
                externalSelector: IERC20.approve.selector,
                selfSelector: IERC20Validator.validateERC20Allowance.selector,
                configData: erc20ApproveConfig
            });
        }

        // swap validation
        {
            bytes memory swapConfig = abi.encode(1000); // 10%
            registrations[_registrationIndex++] = IValidator.ValidationRegistration({
                target: _swapRouter,
                externalSelector: IVelodromeRouter.exactInputSingle.selector,
                selfSelector: IVelodromeValidator.validateExactInputSingleVelodrome.selector,
                configData: swapConfig
            });
        }

        // mint validation
        {
            bytes memory mintConfig = abi.encode(1000); // 10%
            registrations[_registrationIndex++] = IValidator.ValidationRegistration({
                target: _positionManager,
                externalSelector: IVelodromePositionManager.mint.selector,
                selfSelector: IVelodromeValidator.validateMintVelodrome.selector,
                configData: mintConfig
            });
        }

        // withdraw validation
        {
            // transfer fee token to fee recipient validation
            address[] memory allowedRecipients = new address[](1);
            allowedRecipients[0] = _feeRecipient;
            bytes memory erc20TransferConfig = abi.encode(
                IERC20Validator.ERC20TransferConfig({
                    maxAmount: type(uint256).max,
                    allowedRecipients: allowedRecipients
                })
            );
            registrations[_registrationIndex++] = IValidator.ValidationRegistration({
                target: _feeToken,
                externalSelector: IERC20.transfer.selector,
                selfSelector: IERC20Validator.validateERC20Transfer.selector,
                configData: erc20TransferConfig
            });

            // withdraw validation
            registrations[_registrationIndex++] = IValidator.ValidationRegistration({
                target: _gauge,
                externalSelector: IVelodromeGauge.withdraw.selector,
                selfSelector: IValidator.noValidate.selector,
                configData: ''
            });

            // decrease liquidity
            registrations[_registrationIndex++] = IValidator.ValidationRegistration({
                target: _positionManager,
                externalSelector: IPositionManager.decreaseLiquidity.selector,
                selfSelector: IVelodromeValidator.validateDecreaseLiquidityVelodrome.selector,
                configData: abi.encode(1000) // 10%
            });

            // collect
            registrations[_registrationIndex++] = IValidator.ValidationRegistration({
                target: _positionManager,
                externalSelector: IPositionManager.collect.selector,
                selfSelector: IVelodromeValidator.validateCollectVelodrome.selector,
                configData: abi.encode(1000) // 10%
            });

            // burn
            registrations[_registrationIndex++] = IValidator.ValidationRegistration({
                target: _positionManager,
                externalSelector: IPositionManager.burn.selector,
                selfSelector: IValidator.noValidate.selector,
                configData: ''
            });
        }

        _validator.registerValidations(registrations);
        _validator.registerOracle(_token0, _token1, address(_bridgeOracle));
    }

    function testIntegrationApproveAndSwapSuccess() public {
        vm.createSelectFork('https://base.blockpi.network/v1/rpc/286eabc42a0f15b60f0ff2ab59afc08225381836', 28995685);
        _setUpContracts();

        vm.prank(_executorPlugin);
        vm.expectEmit(_safeWallet);
        emit ExecutionFromModuleSuccess(_executorPlugin);
        // approve and swap
        _safeWallet.functionCall(_getMultiSendSwapCalldata());
    }

    function testIntegrationApproveAndMintSuccess() public {
        vm.createSelectFork('https://base.blockpi.network/v1/rpc/286eabc42a0f15b60f0ff2ab59afc08225381836', 28995698);
        _setUpContracts();
        vm.prank(_executorPlugin);
        vm.expectEmit(_safeWallet);
        emit ExecutionFromModuleSuccess(_executorPlugin);
        // approve and mint
        _safeWallet.functionCall(_getMultiSendMintCalldata());
    }

    function testIntegrationUnstakeAndClosePositionSuccess() public {
        vm.createSelectFork('https://base.blockpi.network/v1/rpc/286eabc42a0f15b60f0ff2ab59afc08225381836', 29001423);
        _setUpContracts();
        vm.prank(_executorPlugin);
        vm.expectEmit(_safeWallet);
        emit ExecutionFromModuleSuccess(_executorPlugin);
        // unstake and close position
        _safeWallet.functionCall(_getUnstakeCalldata());
    }

    function _getMultiSendSwapCalldata() internal pure returns (bytes memory) {
        return
            hex'5229073f00000000000000000000000040a2accbd92bca938b02010e17a5b8929b49130d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000002448d80ff0a000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001f200833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044095ea7b3000000000000000000000000be6d8f0d05cc4be24d5167a3ef062215be6d18a5000000000000000000000000000000000000000000000000000000000000110c00be6d8f0d05cc4be24d5167a3ef062215be6d18a500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000104a026383e000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000042000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000064000000000000000000000000150fc1542b18fc2f30b383c9d13f71b0930f42550000000000000000000000000000000000000000000000000000000067ff3ed7000000000000000000000000000000000000000000000000000000000000110c0000000000000000000000000000000000000000000000000000027bc3bc90710000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000';
    }

    function _getMultiSendMintCalldata() internal pure returns (bytes memory) {
        return
            hex'5229073f00000000000000000000000040a2accbd92bca938b02010e17a5b8929b49130d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000003648d80ff0a0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000030b00420000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044095ea7b3000000000000000000000000827922686190790b37229fd06084350e74485b720000000000000000000000000000000000000000000000000000027e6d8e9abf00833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044095ea7b3000000000000000000000000827922686190790b37229fd06084350e74485b72000000000000000000000000000000000000000000000000000000000000160400827922686190790b37229fd06084350e74485b7200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000184b5007d1f0000000000000000000000004200000000000000000000000000000000000006000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000000000000000000000000000000000000000000064fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffcdd44fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffcf1300000000000000000000000000000000000000000000000000000027e6d8e9abf0000000000000000000000000000000000000000000000000000000000001604000000000000000000000000000000000000000000000000000002649aa1b86f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000150fc1542b18fc2f30b383c9d13f71b0930f42550000000000000000000000000000000000000000000000000000000067ff3eee000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000';
    }

    function _getUnstakeCalldata() internal pure returns (bytes memory) {
        return
            hex'5229073f00000000000000000000000040a2accbd92bca938b02010e17a5b8929b49130d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000003a48d80ff0a0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000035d00f33a96b5932d9e9b9a0eda447abd8c9d48d2e0c8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000242e1a7d4d0000000000000000000000000000000000000000000000000000000000ac76be00940181a94a35a4569e4529a3cdfb74e38fd9863100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044a9059cbb0000000000000000000000006f00b52f64a041e7623a9747ecbda91d619e2caa0000000000000000000000000000000000000000000000000000007a3dfe6d6100827922686190790b37229fd06084350e74485b72000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a40c49ccbe0000000000000000000000000000000000000000000000000000000000ac76be000000000000000000000000000000000000000000000000000000003e61718d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000067ff6bab00827922686190790b37229fd06084350e74485b7200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000084fc6f78650000000000000000000000000000000000000000000000000000000000ac76be000000000000000000000000150fc1542b18fc2f30b383c9d13f71b0930f425500000000000000000000000000000000ffffffffffffffffffffffffffffffff00000000000000000000000000000000ffffffffffffffffffffffffffffffff00827922686190790b37229fd06084350e74485b720000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002442966c680000000000000000000000000000000000000000000000000000000000ac76be00000000000000000000000000000000000000000000000000000000000000';
    }
}
