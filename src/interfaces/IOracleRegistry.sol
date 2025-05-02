// SPDX-License-Identifier: MIT

pragma solidity >=0.8.24;

interface IOracleRegistry {
    /// @notice Registers a new oracle for the given token pair
    /// @param token0 The first token in the pair
    /// @param token1 The second token in the pair
    /// @param adapter The address of the oracle adapter
    function registerOracle(address token0, address token1, address adapter) external;

    /// @notice Returns the oracle for the given token pair
    /// @param token0 The first token in the pair
    /// @param token1 The second token in the pair
    /// @return oracle The address of the oracle for the given token pair
    function getOracle(address token0, address token1) external view returns (address);
}
