// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { Test } from 'forge-std/Test.sol';

import { BytesLib } from 'src/libraries/BytesLib.sol';

contract BytesLibTest is Test {
    function testPopHeadOverflow() public {
        bytes memory b = hex'01';
        vm.expectRevert(BytesLib.InvalidLength.selector);
        BytesLib.popHead(b, 3);
    }

    function testToUint256() public pure {
        uint256 x = 0x123456789abcdef;
        bytes memory b = abi.encode(x);
        uint256 y = BytesLib.toUint256(b);
        assertEq(y, x);
    }

    function testToSelector() public pure {
        bytes4 sel = bytes4(keccak256('transfer(address,uint256)'));
        bytes memory b = abi.encodePacked(sel);
        bytes4 s = BytesLib.toSelector(b);
        assertEq(s, sel);
    }

    function testPopHead() public pure {
        bytes memory b = hex'11223344aabbcc';
        (bytes memory head, bytes memory rest) = BytesLib.popHead(b, 4);
        assertEq(head, hex'11223344');
        assertEq(rest, hex'aabbcc');
    }

    function testPopHeadZero() public pure {
        bytes memory b = hex'deadbeef';
        (bytes memory head, bytes memory rest) = BytesLib.popHead(b, 0);
        assertEq(head, hex'');
        assertEq(rest, hex'deadbeef');
    }

    function testPopHeadExact() public pure {
        bytes memory b = hex'cafebabe';
        (bytes memory head, bytes memory rest) = BytesLib.popHead(b, b.length);
        assertEq(head, b);
        assertEq(rest, hex'');
    }

    function testPopHeadUint256() public pure {
        uint256 a = 0x1111;
        uint256 c = 0x2222;
        bytes memory b = abi.encodePacked(a, c);
        (uint256 head, bytes memory rest) = BytesLib.popHeadUint256(b);
        assertEq(head, a);
        assertEq(rest, abi.encodePacked(c));
    }

    function testPopHeadSelector() public pure {
        bytes4 a = bytes4(0xabcdef12);
        bytes4 d = bytes4(0xdeadbeef);
        bytes memory b = abi.encodePacked(a, d);

        (bytes4 head, bytes memory rest) = BytesLib.popHeadSelector(b);

        assertEq(head, a);
        assertEq(rest, abi.encodePacked(d));
    }
}
