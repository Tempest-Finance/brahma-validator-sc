// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { Script } from 'forge-std/Script.sol';
import { console } from 'forge-std/console.sol';
import { Validator } from 'src/Validator.sol';
import { MultiSendCallOnly } from 'src/MultiSendCallOnly.sol';
import { ProxyAdmin } from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

contract DeployScript is Script {
    function run() external {
        bytes32 salt = keccak256(abi.encodePacked(vm.envString('SALT')));

        // Read governor address from environment variable
        address governor = vm.envAddress('GOVERNOR_ADDRESS');
        require(governor != address(0), 'DeployScript: GOVERNOR_ADDRESS env variable not set or is zero address');
        console.log('Using Governor Address:', governor);

        vm.startBroadcast();

        // 1. Deploy Validator Implementation
        Validator validatorImplementation = new Validator();
        console.log('Validator Implementation deployed at:', address(validatorImplementation));

        // 2. Encode Validator Initializer Data
        bytes memory validatorInitData = abi.encodeWithSelector(
            Validator.initialize.selector,
            governor // governor address
        );

        // 3. Deploy Validator Proxy (TransparentUpgradeableProxy)
        TransparentUpgradeableProxy validatorProxy = new TransparentUpgradeableProxy{ salt: salt }(
            address(validatorImplementation),
            governor,
            validatorInitData
        );
        address validatorProxyAddress = address(validatorProxy);
        console.log('Validator Proxy deployed at:', validatorProxyAddress);

        // 5. Deploy MultiSendCallOnly, linking it to the Validator Proxy
        MultiSendCallOnly multiSend = new MultiSendCallOnly{ salt: salt }(validatorProxyAddress);
        console.log('MultiSendCallOnly deployed at:', address(multiSend));

        vm.stopBroadcast();
    }
}
