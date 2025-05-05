// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

interface IERC721Validator {
    error ERC721NotAllowed();

    function validateERC721Allowance(address token, bytes memory callData, bytes memory configData) external view;
}
