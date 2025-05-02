// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

interface IVelodromeValidator {
    /**
     * @notice Validates parameters for minting a new position on Velodrome.
     */
    function validateMintVelodrome(address target, bytes memory data, bytes memory configData) external view;

    /**
     * @notice Validates parameters for an exactInputSingle swap on Velodrome Router.
     */
    function validateExactInputSingleVelodrome(
        address target,
        bytes memory data,
        bytes memory configData
    ) external view;

    /**
     * @notice Validates parameters for increasing liquidity on Velodrome.
     */
    function validateIncreaseLiquidityVelodrome(
        address target,
        bytes memory data,
        bytes memory configData
    ) external view;

    /**
     * @notice Validates parameters for decreasing liquidity on Velodrome.
     */
    function validateDecreaseLiquidityVelodrome(
        address target,
        bytes memory data,
        bytes memory configData
    ) external view;

    /**
     * @notice Validates parameters for collecting fees on Velodrome.
     */
    function validateCollectVelodrome(address target, bytes memory data, bytes memory configData) external view;
}
