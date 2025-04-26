// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { Bytes } from '@openzeppelin/contracts/utils/Bytes.sol';

library BytesLib {
    using Bytes for bytes;

    error InvalidLength();

    function slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory) {
        return _bytes.slice(_start, _start + _length);
    }

    function toAddress(bytes memory _bytes) internal pure returns (address) {
        require(_bytes.length == 20, InvalidLength());
        return address(bytes20(_bytes));
    }

    function toUint256(bytes memory _bytes) internal pure returns (uint256) {
        require(_bytes.length == 32, InvalidLength());
        return uint256(bytes32(_bytes));
    }

    function toSelector(bytes memory _bytes) internal pure returns (bytes4) {
        require(_bytes.length == 4, InvalidLength());
        return bytes4(_bytes);
    }

    function popHeadUint256(bytes memory _bytes) internal pure returns (uint256, bytes memory) {
        (bytes memory value, bytes memory rest) = popHead(_bytes, 32);
        return (toUint256(value), rest);
    }

    function popHeadSelector(bytes memory _bytes) internal pure returns (bytes4, bytes memory) {
        (bytes memory value, bytes memory rest) = popHead(_bytes, 4);

        return (toSelector(value), rest);
    }

    function popHead(
        bytes memory _bytes,
        uint256 _length
    ) internal pure returns (bytes memory data, bytes memory rest) {
        require(_length <= _bytes.length, InvalidLength());
        data = _bytes.slice(0, _length);
        rest = _bytes.slice(_length, _bytes.length);
    }
}
