// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { Bytes } from '@openzeppelin/contracts/utils/Bytes.sol';

library BytesLib {
    using Bytes for bytes;

    error InvalidLength();

    function _slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory) {
        return _bytes.slice(_start, _start + _length);
    }

    function _toAddress(bytes memory _bytes) internal pure returns (address) {
        require(_bytes.length == 20, InvalidLength());
        return address(bytes20(_bytes));
    }

    function _toUint256(bytes memory _bytes) internal pure returns (uint256) {
        require(_bytes.length == 32, InvalidLength());
        return uint256(bytes32(_bytes));
    }

    function _toSelector(bytes memory _bytes) internal pure returns (bytes4) {
        require(_bytes.length == 4, InvalidLength());
        return bytes4(_bytes);
    }

    function _popHeadUint256(bytes memory _bytes) internal pure returns (uint256, bytes memory) {
        (bytes memory value, bytes memory rest) = _popHead(_bytes, 32);
        return (_toUint256(value), rest);
    }

    function _popHeadSelector(bytes memory _bytes) internal pure returns (bytes4, bytes memory) {
        (bytes memory value, bytes memory rest) = _popHead(_bytes, 4);

        return (_toSelector(value), rest);
    }

    function _popHead(
        bytes memory _bytes,
        uint256 _length
    ) internal pure returns (bytes memory data, bytes memory rest) {
        require(_length <= _bytes.length, InvalidLength());
        data = _bytes.slice(0, _length);
        rest = _bytes.slice(_length, _bytes.length);
    }
}
