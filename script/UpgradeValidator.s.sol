// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

import { Script } from 'forge-std/Script.sol';
import { ProxyAdmin } from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import { ITransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import { Validator } from 'src/Validator.sol';

contract UpgradeValidator is Script {
    function run() public {
        vm.startBroadcast();

        Validator newImplementation = new Validator();
        address proxy = 0xC5a5973BA7675b5Fa79162866e101817D83ce834;
        address proxyAdmin = 0x715115bad19315E5cA3e39ADaf4586a3Da29af51;
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), address(newImplementation), '');

        vm.stopBroadcast();
    }
}
