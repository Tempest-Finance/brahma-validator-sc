// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { Test } from 'forge-std/Test.sol';
import { BytesLib } from 'src/libraries/BytesLib.sol';

contract BytesLibTest is Test {
    uint256 internal constant _TEST_UINT = 0x123456789abcdef;
    address internal constant _TEST_ADDRESS = 0x112233445566778899aABBccDdeeff1122334455;
    bytes4 internal constant _TEST_SELECTOR = bytes4(keccak256('transfer(address,uint256)'));
    uint256 internal constant _TEST_UINT_A = 0x1111;
    uint256 internal constant _TEST_UINT_C = 0x2222;
    bytes4 internal constant _TEST_SELECTOR_A = bytes4(0xabcdef12);
    bytes4 internal constant _TEST_SELECTOR_D = bytes4(0xdeadbeef);

    function testPopHeadOverflow() public {
        bytes memory b = hex'01';
        vm.expectRevert(BytesLib.InvalidLength.selector);
        BytesLib._popHead(b, 3);
    }

    function testToUint256() public pure {
        bytes memory b = abi.encode(_TEST_UINT);
        uint256 y = BytesLib._toUint256(b);
        assertEq(y, _TEST_UINT);
    }

    function testToUint256Revert() public {
        bytes memory b = hex'1234';
        vm.expectRevert(BytesLib.InvalidLength.selector);
        BytesLib._toUint256(b);
    }

    function testToAddress() public pure {
        bytes memory b = abi.encodePacked(_TEST_ADDRESS);
        address a = BytesLib._toAddress(b);
        assertEq(a, _TEST_ADDRESS);
    }

    function testToAddressRevert() public {
        bytes memory b = hex'1234';
        vm.expectRevert(BytesLib.InvalidLength.selector);
        BytesLib._toAddress(b);
    }

    function testToSelector() public pure {
        bytes memory b = abi.encodePacked(_TEST_SELECTOR);
        bytes4 s = BytesLib._toSelector(b);
        assertEq(s, _TEST_SELECTOR);
    }

    function testToSelectorRevert() public {
        bytes memory b = hex'123456';
        vm.expectRevert(BytesLib.InvalidLength.selector);
        BytesLib._toSelector(b);
    }

    function testPopHead() public pure {
        bytes memory b = hex'11223344aabbcc';
        (bytes memory head, bytes memory rest) = BytesLib._popHead(b, 4);
        assertEq(head, hex'11223344');
        assertEq(rest, hex'aabbcc');
    }

    function testPopHeadZero() public pure {
        bytes memory b = hex'deadbeef';
        (bytes memory head, bytes memory rest) = BytesLib._popHead(b, 0);
        assertEq(head, hex'');
        assertEq(rest, hex'deadbeef');
    }

    function testPopHeadExact() public pure {
        bytes memory b = hex'cafebabe';
        (bytes memory head, bytes memory rest) = BytesLib._popHead(b, b.length);
        assertEq(head, b);
        assertEq(rest, hex'');
    }

    function testPopHeadUint256() public pure {
        bytes memory b = abi.encodePacked(_TEST_UINT_A, _TEST_UINT_C);
        (uint256 head, bytes memory rest) = BytesLib._popHeadUint256(b);
        assertEq(head, _TEST_UINT_A);
        assertEq(rest, abi.encodePacked(_TEST_UINT_C));
    }

    function testPopHeadUint256Revert() public {
        bytes memory b = hex'01020304';
        vm.expectRevert(BytesLib.InvalidLength.selector);
        BytesLib._popHeadUint256(b);
    }

    function testPopHeadSelector() public pure {
        bytes memory b = abi.encodePacked(_TEST_SELECTOR_A, _TEST_SELECTOR_D);

        (bytes4 head, bytes memory rest) = BytesLib._popHeadSelector(b);

        assertEq(head, _TEST_SELECTOR_A);
        assertEq(rest, abi.encodePacked(_TEST_SELECTOR_D));
    }

    function testPopHeadSelectorRevert() public {
        bytes memory b = hex'0102';
        vm.expectRevert(BytesLib.InvalidLength.selector);
        BytesLib._popHeadSelector(b);
    }
}
