// SPDX-License-Identifier: MIT

pragma solidity >=0.8.24;

interface IOpenOcean {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 guaranteedAmount;
        uint256 flags;
        address referrer;
        bytes permit;
    }

    struct CallDescription {
        uint256 target;
        uint256 gasLimit;
        uint256 value;
        bytes data;
    }

    function swap(
        address caller,
        SwapDescription calldata desc,
        CallDescription[] calldata calls
    ) external payable returns (uint256 returnAmount);
}
