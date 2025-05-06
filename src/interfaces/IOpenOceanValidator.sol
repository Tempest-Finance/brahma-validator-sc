// SPDX-License-Identifier: MIT

pragma solidity >=0.8.24;

interface IOpenOceanValidator {
    error PermitNotAllowed();
    error PartialFillNotAllowed();

    function validateOpenOceanSwap(address target, bytes memory data, bytes memory configData) external view;
}
