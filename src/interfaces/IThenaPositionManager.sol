// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { IPositionManager } from './IPositionManager.sol';

uint256 constant POSITION_RESULT_LENGTH = 352;

interface IThenaPositionManager is IPositionManager {
    struct MintParams {
        address token0;
        address token1;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct PositionData {
        // 352 bytes = 11 * 32 bytes (Assuming one less field than Velodrome)
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    function mint(
        MintParams calldata params
    ) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Returns the deployer address for the router
    /// @return The deployer address
    function poolDeployer() external view returns (address);
}
