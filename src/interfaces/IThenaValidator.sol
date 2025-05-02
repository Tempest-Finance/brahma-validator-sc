// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

interface IThenaValidator {
    /**
     * @notice Validates parameters for minting a new position on Thena.
     */
    function validateMintThena(address target, bytes memory data, bytes memory configData) external view;

    /**
     * @notice Validates parameters for an exactInputSingle swap on Thena Router.
     */
    function validateExactInputSingleThena(address target, bytes memory data, bytes memory configData) external view;

    /**
     * @notice Validates parameters for increasing liquidity on Thena.
     */
    function validateIncreaseLiquidityThena(address target, bytes memory data, bytes memory configData) external view;

    /**
     * @notice Validates parameters for decreasing liquidity on Thena.
     */
    function validateDecreaseLiquidityThena(address target, bytes memory data, bytes memory configData) external view;

    /**
     * @notice Validates parameters for collecting fees on Thena.
     */
    function validateCollectThena(address target, bytes memory data, bytes memory configData) external view;
}
