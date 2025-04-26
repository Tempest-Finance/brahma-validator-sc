// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IValidator {
    enum Protocol {
        Velodrome,
        Thena,
        Shadow
    }
    function multiSend(bytes memory transactions) external payable;
}
