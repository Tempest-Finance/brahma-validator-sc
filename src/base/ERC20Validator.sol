// SPDX-License-Identifier: MIT

pragma solidity >=0.8.24;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { ValidatorBase } from 'src/base/ValidatorBase.sol';
import { IERC20Validator } from 'src/interfaces/IERC20Validator.sol';

abstract contract ERC20Validator is ValidatorBase, IERC20Validator {
    function validateTransfer(address /* token */, bytes memory data, bytes memory configData) public pure {
        // decode the data argument (which contains the encoded transfer arguments)
        (address recipient, uint256 amount) = abi.decode(data, (address, uint256));
        // decode the config data directly
        ERC20TransferConfig memory config = abi.decode(configData, (ERC20TransferConfig));

        // validate the amount
        if (amount > config.maxAmount) {
            revert TransferTooMuch();
        }

        // validate the recipient
        for (uint256 i = 0; i < config.allowedRecipients.length; i++) {
            if (config.allowedRecipients[i] == recipient) {
                // spender is valid, just return
                return;
            }
        }
        revert ERC20NotAllowed();
    }

    function validateAllowance(address, /* token */ bytes memory data, bytes memory configData) public pure {
        // decode the data argument (which contains the encoded approve arguments)
        (address spender, uint256 amount) = abi.decode(data, (address, uint256));
        // decode the config data directly
        ERC20AllowanceConfig memory config = abi.decode(configData, (ERC20AllowanceConfig));

        // validate the amount
        if (amount > config.maxAmount) {
            revert ApproveTooMuch();
        }

        // validate the spender
        for (uint256 i = 0; i < config.allowedSpenders.length; i++) {
            if (config.allowedSpenders[i] == spender) {
                // spender is valid, just return
                return;
            }
        }

        revert ERC20NotAllowed();
    }
}
