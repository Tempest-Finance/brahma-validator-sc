// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

interface IShadowValidator {
    struct ShadowMintConfig {
        address recipient;
        uint256 devPriceThresholdBps;
    }

    struct ShadowExactInputSingleConfig {
        address recipient;
        uint256 maxSlippageBps;
    }

    /**
     * @notice Validates parameters for minting a new position on Shadow.
     */
    function validateMintShadow(address target, bytes memory data, bytes memory configData) external view;

    /**
     * @notice Validates parameters for an exactInputSingle swap on Shadow Router.
     */
    function validateExactInputSingleShadow(address target, bytes memory data, bytes memory configData) external view;

    /**
     * @notice Validates parameters for increasing liquidity on Shadow.
     */
    function validateIncreaseLiquidityShadow(address target, bytes memory data, bytes memory configData) external view;

    /**
     * @notice Validates parameters for decreasing liquidity on Shadow.
     */
    function validateDecreaseLiquidityShadow(address target, bytes memory data, bytes memory configData) external view;

    /**
     * @notice Validates parameters for collecting fees on Shadow.
     */
    function validateCollectShadow(address target, bytes memory data, bytes memory configData) external view;
}
