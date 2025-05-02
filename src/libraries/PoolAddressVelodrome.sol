// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import { Clones } from '@openzeppelin/contracts/proxy/Clones.sol';

import { IVelodromeFactory } from 'src/interfaces/IVelodromeFactory.sol';

/// @title Provides functions for deriving a pool address from the factory, tokens, and the fee
library PoolAddress {
    /// @notice The identifying key of the pool
    struct PoolKey {
        address token0;
        address token1;
        int24 tickSpacing;
    }

    /// @notice Deterministically computes the pool address given the factory and PoolKey
    /// @param factory The CL factory contract address
    /// @param key The PoolKey
    /// @return pool The contract address of the V3 pool
    function _computeAddress(address factory, PoolKey memory key) internal view returns (address pool) {
        pool = Clones.predictDeterministicAddress(
            IVelodromeFactory(factory).poolImplementation(),
            keccak256(abi.encode(key.token0, key.token1, key.tickSpacing)),
            factory
        );
    }

    /// @notice Returns PoolKey: the ordered tokens with the matched fee levels
    /// @param tokenA The first token of a pool, unsorted
    /// @param tokenB The second token of a pool, unsorted
    /// @param tickSpacing The tick spacing of the pool
    /// @return Poolkey The pool details with ordered token0 and token1 assignments
    function _getPoolKey(address tokenA, address tokenB, int24 tickSpacing) internal pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({ token0: tokenA, token1: tokenB, tickSpacing: tickSpacing });
    }
}
