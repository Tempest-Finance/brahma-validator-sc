// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { ProxyAdmin } from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import { Script } from 'forge-std/Script.sol';
import { console } from 'forge-std/console.sol';
import { Validator } from 'src/Validator.sol';
import { MultiSendCallOnly } from 'src/MultiSendCallOnly.sol';
import { BridgeOracle } from 'src/BridgeOracle.sol';
import { OracleOne } from 'src/OracleOne.sol';

contract DeployOracleScript is Script {
    address public weth = address(0x4200000000000000000000000000000000000006);
    address public usdc = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    address public cbBTC = address(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf);
    address public usdPlus = address(0xB79DD08EA68A908A97220C76d19A6aA9cBDE4376);
    address public virtual_ = address(0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b);
    address public wstETH = address(0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452);
    address public usdt = address(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2);
    address public aero = address(0x940181a94A35A4569E4529A3CDfB74e38FD98631);

    address public wethOracle = address(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70);
    uint64 public wethHeartbeat = 1205;

    address public usdcOracle = address(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B);
    uint64 public usdcHeartbeat = 86405;

    address public cbBTCOracle = address(0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D);
    uint64 public cbBTCHeartbeat = 1205;

    address public usdPlusOracle = address(0xd9a66Ff1D660aD943F48e9c606D09eA672f312E8);
    uint64 public usdPlusHeartbeat = 86405;

    address public virtualOracle = address(0xEaf310161c9eF7c813A14f8FEF6Fb271434019F7);
    uint64 public virtualHeartbeat = 86405;

    address public wstETHOracle = address(0x43a5C292A453A3bF3606fa856197f09D7B74251a);
    uint64 public wstETHHeartbeat = 86405;

    address public usdtOracle = address(0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9);
    uint64 public usdtHeartbeat = 86405;

    address public aeroOracle = address(0x4EC5970fC728C5f65ba413992CD5fF6FD70fcfF0);
    uint64 public aeroHeartbeat = 86405;

    address public sequencerUptimeFeeds = address(0xBCF85224fc0756B9Fa45aA7892530B47e10b6433);
    uint64 public sequencerUptimeLimit = 3600;

    function run() external {
        // Read governor address from environment variable
        address governor = vm.envAddress('GOVERNOR_ADDRESS');

        require(governor != address(0), 'DeployScript: GOVERNOR_ADDRESS env variable not set or is zero address');
        console.log('Using Governor Address:', governor);

        vm.startBroadcast();

        address validator = 0xC5a5973BA7675b5Fa79162866e101817D83ce834;

        // https://docs.chain.link/data-feeds/price-feeds/addresses?page=1&network=base
        // https://docs.chain.link/data-feeds/l2-sequencer-feeds

        address constantOracle = address(new OracleOne('Constant oracle'));

        {
            // WETH , USDC
            address wethUsdcOracle = address(
                new BridgeOracle(
                    wethOracle,
                    usdcOracle,
                    sequencerUptimeFeeds,
                    wethHeartbeat,
                    usdcHeartbeat,
                    sequencerUptimeLimit,
                    true,
                    'WETH_USDC',
                    governor
                )
            );
            Validator(validator).registerOracle(weth, usdc, wethUsdcOracle);
        }

        {
            // WETH , cbBTC
            address wethCbBTCOracle = address(
                new BridgeOracle(
                    wethOracle,
                    cbBTCOracle,
                    sequencerUptimeFeeds,
                    wethHeartbeat,
                    cbBTCHeartbeat,
                    sequencerUptimeLimit,
                    true,
                    'WETH_cbBTC',
                    governor
                )
            );
            Validator(validator).registerOracle(weth, cbBTC, wethCbBTCOracle);
        }

        {
            // USDC,cbBTC
            address usdcCbBTCOracle = address(
                new BridgeOracle(
                    usdcOracle,
                    cbBTCOracle,
                    sequencerUptimeFeeds,
                    usdcHeartbeat,
                    cbBTCHeartbeat,
                    sequencerUptimeLimit,
                    true,
                    'USDC_cbBTC',
                    governor
                )
            );
            Validator(validator).registerOracle(usdc, cbBTC, usdcCbBTCOracle);
        }

        {
            // WETH,USD+
            address wethUsdPlusOracle = address(
                new BridgeOracle(
                    wethOracle,
                    usdPlusOracle,
                    sequencerUptimeFeeds,
                    wethHeartbeat,
                    usdPlusHeartbeat,
                    sequencerUptimeLimit,
                    true,
                    'WETH_USD+',
                    governor
                )
            );
            Validator(validator).registerOracle(weth, usdPlus, wethUsdPlusOracle);
        }

        {
            // VIRTUAL,WETH
            address virtualWethOracle = address(
                new BridgeOracle(
                    virtualOracle,
                    wethOracle,
                    sequencerUptimeFeeds,
                    virtualHeartbeat,
                    wethHeartbeat,
                    sequencerUptimeLimit,
                    true,
                    'VIRTUAL_WETH',
                    governor
                )
            );
            Validator(validator).registerOracle(virtual_, weth, virtualWethOracle);
        }

        {
            // WETH,wstETH
            address wethWstEthOracle = address(
                new BridgeOracle(
                    constantOracle,
                    wstETHOracle,
                    sequencerUptimeFeeds,
                    3600,
                    wstETHHeartbeat,
                    sequencerUptimeLimit,
                    true,
                    'WETH_USDC',
                    governor
                )
            );
            Validator(validator).registerOracle(weth, wstETH, wethWstEthOracle);
        }

        {
            // WETH,USDT
            address wethUsdtOracle = address(
                new BridgeOracle(
                    wethOracle,
                    usdtOracle,
                    sequencerUptimeFeeds,
                    wethHeartbeat,
                    usdtHeartbeat,
                    sequencerUptimeLimit,
                    true,
                    'WETH_USDT',
                    governor
                )
            );
            Validator(validator).registerOracle(weth, usdt, wethUsdtOracle);
        }

        {
            // USDC,USD+
            address usdcUsdPlusOracle = address(
                new BridgeOracle(
                    usdcOracle,
                    usdPlusOracle,
                    sequencerUptimeFeeds,
                    usdcHeartbeat,
                    usdPlusHeartbeat,
                    sequencerUptimeLimit,
                    true,
                    'USDC_USD+',
                    governor
                )
            );
            Validator(validator).registerOracle(usdc, usdPlus, usdcUsdPlusOracle);
        }

        {
            // WETH,AERO
            address wethAeroOracle = address(
                new BridgeOracle(
                    wethOracle,
                    aeroOracle,
                    sequencerUptimeFeeds,
                    wethHeartbeat,
                    aeroHeartbeat,
                    sequencerUptimeLimit,
                    true,
                    'WETH_AERO',
                    governor
                )
            );
            Validator(validator).registerOracle(weth, aero, wethAeroOracle);
        }

        vm.stopBroadcast();
    }
}
