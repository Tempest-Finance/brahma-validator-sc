// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { IERC721Validator } from 'src/interfaces/IERC721Validator.sol';

abstract contract ERC721Validator is IERC721Validator {
    function validateERC721Allowance(address /* token */, bytes memory data, bytes memory configData) public pure {
        // decode the data argument (which contains the encoded approve arguments)
        (address spender, ) = abi.decode(data, (address, uint256));
        // decode the config data directly
        address[] memory allowedSpenders = abi.decode(configData, (address[]));

        // validate the spender
        for (uint256 i = 0; i < allowedSpenders.length; i++) {
            if (allowedSpenders[i] == spender) {
                return;
            }
        }

        revert ERC721NotAllowed();
    }
}
