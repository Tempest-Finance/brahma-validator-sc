// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';

import { IOracleAdapter } from 'src/interfaces/IOracleAdapter.sol';

library OracleLib {
    struct OracleMap {
        address token0;
        address token1;
        IOracleAdapter oracle;
    }

    struct OraclePrice {
        uint256 price;
        uint8 decimals;
    }

    error NO_ORACLE();
    error ORACLE_PAIR_ORDER();

    function getPrice(address token0, address token1) internal view returns (OraclePrice memory) {
        require(token0 < token1, ORACLE_PAIR_ORDER());
        IOracleAdapter oracle = getOracle(token0, token1);
        uint256 price = uint256(oracle.latestAnswer());
        uint8 decimals = oracle.decimals();
        return OraclePrice({ price: price, decimals: decimals });
    }

    function getAllOracle() internal pure returns (OracleMap[] memory oracleMap) {
        oracleMap = new OracleMap[](0);
        oracleMap[0] = OracleMap({ token0: address(0), token1: address(0), oracle: IOracleAdapter(address(0)) });
        oracleMap[1] = OracleMap({ token0: address(0), token1: address(0), oracle: IOracleAdapter(address(0)) });
        oracleMap[2] = OracleMap({ token0: address(0), token1: address(0), oracle: IOracleAdapter(address(0)) });
    }

    function validateConfiguredOracles() internal pure {
        OracleMap[] memory oracleMap = getAllOracle();
        for (uint256 i = 0; i < oracleMap.length; i++) {
            require(oracleMap[i].token0 < oracleMap[i].token1, ORACLE_PAIR_ORDER());
        }
    }

    function getOracle(address base, address quote) private pure returns (IOracleAdapter oracle) {
        OracleMap[] memory oracleMap = getAllOracle();
        for (uint256 i = 0; i < oracleMap.length; i++) {
            if (oracleMap[i].token0 == base && oracleMap[i].token1 == quote) {
                return oracleMap[i].oracle;
            }
        }
        revert NO_ORACLE();
    }
}
