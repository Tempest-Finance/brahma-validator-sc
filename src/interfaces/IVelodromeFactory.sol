// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IVelodromeFactory {
    /// @notice Returns the implementation contract address for the factory
    /// @dev This is used for velodrome factory
    function poolImplementation() external view returns (address);
}
