// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

/// @title Multi Send Call Only - Allows to batch multiple transactions into one, but only calls
contract MultiSendCallOnly {
    address public immutable validator;

    constructor(address validator_) {
        validator = validator_;
    }

    /// @dev Sends multiple transactions and reverts all if one fails.
    /// @param transactions Encoded transactions. Each transaction is encoded as a packed bytes of
    ///                     operation has to be uint8(0) in this version (=> 1 byte),
    ///                     to as a address (=> 20 bytes),
    ///                     value as a uint256 (=> 32 bytes),
    ///                     data length as a uint256 (=> 32 bytes),
    ///                     data as bytes.
    ///                     see abi.encodePacked for more information on packed encoding
    /// @notice The code is for most part the same as the normal MultiSend (to keep compatibility),
    ///         but reverts if a transaction tries to use a delegatecall.
    /// @notice This method is payable as delegatecalls keep the msg.value from the previous call
    ///         If the calling method (e.g. execTransaction) received ETH this would revert otherwise
    function multiSend(bytes memory transactions) public payable {
        address _validator = validator;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            let length := mload(transactions)
            let i := 0x20
            for {
                // Pre block is not used in "while mode"
            } lt(i, length) {
                // Post block is not used in "while mode"
            } {
                let dataLength := mload(add(transactions, add(i, 0x35)))
                let to := shr(0x60, mload(add(transactions, add(i, 0x01))))

                // add scope to avoid stack too deep
                // Validate the transaction
                {
                    let success := 0
                    let validateCalldata := encode_validate(to, add(transactions, add(i, 0x35)), dataLength)
                    // call validate(address,bytes)
                    let validatePayloadSize := mload(validateCalldata)
                    let validateCalldataPtr := add(validateCalldata, 32)
                    success := call(gas(), _validator, 0, validateCalldataPtr, validatePayloadSize, 0, 0)
                    if eq(success, 0) {
                        revert(0, 0)
                    }
                }

                // add scope to avoid stack too deep
                // Call forward transaction
                {
                    // First byte of the data is the operation.
                    // We shift by 248 bits (256 - 8 [operation byte]) it right since mload will always load 32 bytes (a word).
                    // This will also zero out unused data.
                    let operation := shr(0xf8, mload(add(transactions, i)))
                    // We offset the load address by 1 byte (operation byte)

                    // ------------------------------------------------------------
                    // We shift it right by 96 bits (256 - 160 [20 address bytes]) to right-align the data and zero out unused data.
                    // moved code `let to := shr(0x60, mload(add(transactions, add(i, 0x01))))` to the top to avoid stack too deep
                    // ------------------------------------------------------------

                    // We offset the load address by 21 byte (operation byte + 20 address bytes)
                    let value := mload(add(transactions, add(i, 0x15)))
                    if gt(value, 0) {
                        revert(0, 0)
                    }

                    // ------------------------------------------------------------
                    // We offset the load address by 53 byte (operation byte + 20 address bytes + 32 value bytes)
                    // moved code `let dataLength := mload(add(transactions, add(i, 0x35)))` to the top to avoid stack too deep
                    // ------------------------------------------------------------

                    // We offset the load address by 85 byte (operation byte + 20 address bytes + 32 value bytes + 32 data length bytes)
                    let data := add(transactions, add(i, 0x55))
                    let success := 0
                    switch operation
                    case 0 {
                        success := call(gas(), to, value, data, dataLength, 0, 0)
                    }
                    // This version does not allow delegatecalls
                    case 1 {
                        revert(0, 0)
                    }
                    if eq(success, 0) {
                        revert(0, 0)
                    }
                }

                // Next entry starts at 85 byte + data length
                i := add(i, add(0x55, dataLength))
            }

            // Assembly function to encode validate(address,bytes) call
            function encode_validate(target, dataPtr, dataLen) -> res {
                // Calculate padding for data (must be multiple of 32 bytes)
                let paddedLength := mul(div(add(dataLen, 31), 32), 32)

                // Calculate total payload size
                // 4 bytes for selector
                // 32 bytes for address (20 bytes but padded to 32)
                // 32 bytes for data offset
                // 32 bytes for data length
                // paddedLength bytes for actual data
                let payloadSize := add(add(add(4, 64), 32), paddedLength)

                // Allocate memory for result
                // Format: [length_word (32 bytes)][payload]
                res := mload(0x40) // get free memory pointer
                mstore(0x40, add(add(res, 32), payloadSize)) // update free memory pointer

                // Store length of result
                mstore(res, payloadSize)

                // Get pointer to start of payload (skip length word)
                let payloadPtr := add(res, 32)

                // --- BEGIN PAYLOAD ---

                // 1. Store function selector (first 4 bytes)
                // Hard-coded selector value from keccak256("validate(address,bytes)")
                mstore(payloadPtr, 0xcaf9278500000000000000000000000000000000000000000000000000000000)

                // 2. Store address (right-aligned in 32-byte slot)
                mstore(add(payloadPtr, 4), target)

                // 3. Store offset to data (64 bytes from start of args)
                mstore(add(payloadPtr, 36), 64)

                // 4. Store data length
                mstore(add(payloadPtr, 68), dataLen)

                // 5. Copy data bytes - simplified by using paddedLength
                if gt(dataLen, 0) {
                    // Source is dataPtr + 32 (skip length word)
                    let src := add(dataPtr, 32)
                    // Destination is after selector + address + offset + length
                    let dest := add(payloadPtr, 100)

                    // Calculate number of full 32-byte words to copy
                    let words := div(paddedLength, 32)

                    // Copy full 32-byte chunks - more efficient and simpler
                    // Since we allocated based on paddedLength, we can always copy full words
                    for {
                        let j := 0
                    } lt(j, words) {
                        j := add(j, 1)
                    } {
                        mstore(add(dest, mul(j, 32)), mload(add(src, mul(j, 32))))
                    }
                }
            }
        }
    }
}
