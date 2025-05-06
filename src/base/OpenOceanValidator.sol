// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { IOpenOcean } from 'src/interfaces/IOpenOcean.sol';
import { IOpenOceanValidator } from 'src/interfaces/IOpenOceanValidator.sol';
import { ValidatorBase } from 'src/base/ValidatorBase.sol';

abstract contract OpenOceanValidator is ValidatorBase, IOpenOceanValidator {
    uint256 private constant _OPEN_OCEAN_PARTIAL_FILL_FLAG = 0x01;
    function validateOpenOceanSwap(address /* target */, bytes memory data, bytes memory configData) public view {
        (, IOpenOcean.SwapDescription memory desc, ) = abi.decode(
            data,
            (address, IOpenOcean.SwapDescription, IOpenOcean.CallDescription[])
        );

        uint256 maxSlippageBps = abi.decode(configData, (uint256));

        // Validate the permit
        require(desc.permit.length == 0, PermitNotAllowed());

        // Validate the partial fill flag
        require((desc.flags & _OPEN_OCEAN_PARTIAL_FILL_FLAG) == 0, PartialFillNotAllowed());

        // validate recipient
        require(desc.dstReceiver == msg.sender, InvalidRecipient());

        // Validate the swap slippage
        _checkSwapSlippage(desc.srcToken, desc.dstToken, desc.amount, desc.minReturnAmount, maxSlippageBps);
    }
}
