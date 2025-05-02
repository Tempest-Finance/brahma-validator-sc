// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

interface IERC20Validator {
    struct ERC20TransferConfig {
        uint256 maxAmount;
        address[] allowedRecipients;
    }

    struct ERC20AllowanceConfig {
        uint256 maxAmount;
        address[] allowedSpenders;
    }

    error TransferTooMuch();
    error ERC20NotAllowed();
    error ApproveTooMuch();

    /**
     * @notice Validates an ERC20 transfer call.
     * @param token The address of the ERC20 token being transferred.
     * @param callData Abi-encoded transfer parameters (address recipient, uint256 amount).
     * @param configData Abi-encoded ERC20TransferConfig.
     */
    function validateTransfer(address token, bytes memory callData, bytes memory configData) external view;

    /**
     * @notice Validates an ERC20 approve call.
     * @param token The address of the ERC20 token being approved.
     * @param callData Abi-encoded approve parameters (address spender, uint256 amount).
     * @param configData Abi-encoded ERC20AllowanceConfig.
     */
    function validateAllowance(address token, bytes memory callData, bytes memory configData) external view;
}
