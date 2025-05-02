// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { Test } from 'forge-std/Test.sol';
import { Validator } from 'src/Validator.sol';
import { ProxyAdmin } from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import { IAccessControl } from '@openzeppelin/contracts/access/IAccessControl.sol';
import { IERC20Validator } from 'src/interfaces/IERC20Validator.sol'; // Imports ERC20 structs/errors

abstract contract ValidatorTestBase is Test {
    // --- State Variables ---
    Validator internal _validatorImplementation;
    ProxyAdmin internal _proxyAdmin;
    TransparentUpgradeableProxy internal _validatorProxy;
    Validator internal _validator; // Instance accessed via proxy

    // Common addresses used across tests
    address internal _governor = address(0x1001);
    address internal _nonGovernor = address(0xDEAD);

    // --- Custom Errors (Commonly Used) ---
    // Note: ERC20 errors (TransferTooMuch, ApproveTooMuch, ERC20NotAllowed)
    // are available via the IERC20Validator import.
    error ValidationNotConfigured();

    // --- Setup ---
    function setUp() public virtual {
        // Deploy ProxyAdmin
        _proxyAdmin = new ProxyAdmin(_governor);

        // Deploy Validator implementation
        _validatorImplementation = new Validator();

        // Deploy TransparentUpgradeableProxy
        _validatorProxy = new TransparentUpgradeableProxy(address(_validatorImplementation), address(_proxyAdmin), '');

        // Cast the proxy address to the Validator type to interact with it
        _validator = Validator(address(_validatorProxy));

        // Initialize the proxied Validator contract
        _validator.initialize(_governor);
    }
}
