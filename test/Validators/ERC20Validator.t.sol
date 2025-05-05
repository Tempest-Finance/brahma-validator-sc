// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Import Base, keep specific imports
import { ValidatorTestBase } from './ValidatorTestBase.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IERC20Validator } from 'src/interfaces/IERC20Validator.sol';
import { IValidator } from 'src/interfaces/IValidator.sol';
// Rename contract, Inherit from Base
contract ERC20ValidatorTests is ValidatorTestBase {
    // Keep test-specific addresses
    address internal tokenAddress = address(0x70436); // Add internal visibility
    address internal user1 = address(0x111); // Add internal visibility
    address internal user2 = address(0x222); // Add internal visibility
    address internal user3 = address(0x333); // Add internal visibility

    // --- Tests for validateTransfer ---

    function testValidateTransferSuccess() public {
        // 1. Config: Allow user1, user2 up to 100 tokens
        address[] memory allowedRecipients = new address[](2);
        allowedRecipients[0] = user1;
        allowedRecipients[1] = user2;
        uint256 maxAmount = 100 ether;
        IERC20Validator.ERC20TransferConfig memory config = IERC20Validator.ERC20TransferConfig({
            maxAmount: maxAmount,
            allowedRecipients: allowedRecipients
        });

        // 2. Register config as governor
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = IValidator.ValidationRegistration({
            target: tokenAddress,
            externalSelector: IERC20.transfer.selector,
            selfSelector: IERC20Validator.validateERC20Transfer.selector,
            configData: abi.encode(config)
        });
        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 3. Prepare valid callData (transfer 50 tokens to user1)
        uint256 transferAmount = 50 ether;
        bytes memory callData = abi.encodeCall(IERC20.transfer, (user1, transferAmount));

        // 4. Validate - should succeed
        _validator.validate(tokenAddress, callData);
        assertTrue(true); // Explicit success assertion
    }

    function testValidateTransferRevertsAmountTooMuch() public {
        // 1. Config: Allow user1 up to 100 tokens
        address[] memory allowedRecipients = new address[](1);
        allowedRecipients[0] = user1;
        uint256 maxAmount = 100 ether;
        IERC20Validator.ERC20TransferConfig memory config = IERC20Validator.ERC20TransferConfig({
            maxAmount: maxAmount,
            allowedRecipients: allowedRecipients
        });

        // 2. Register config as governor
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = IValidator.ValidationRegistration({
            target: tokenAddress,
            externalSelector: IERC20.transfer.selector,
            selfSelector: IERC20Validator.validateERC20Transfer.selector,
            configData: abi.encode(config)
        });
        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 3. Prepare invalid callData (transfer 101 tokens to user1)
        uint256 transferAmount = 101 ether;
        bytes memory callData = abi.encodeCall(IERC20.transfer, (user1, transferAmount));

        // 4. Validate - should revert
        vm.expectRevert(IERC20Validator.ERC20TransferTooMuch.selector);
        _validator.validate(tokenAddress, callData);
    }

    function testValidateTransferRevertsRecipientNotAllowed() public {
        // 1. Config: Allow user1, user2 up to 100 tokens
        address[] memory allowedRecipients = new address[](2);
        allowedRecipients[0] = user1;
        allowedRecipients[1] = user2;
        uint256 maxAmount = 100 ether;
        IERC20Validator.ERC20TransferConfig memory config = IERC20Validator.ERC20TransferConfig({
            maxAmount: maxAmount,
            allowedRecipients: allowedRecipients
        });

        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = IValidator.ValidationRegistration({
            target: tokenAddress,
            externalSelector: IERC20.transfer.selector,
            selfSelector: IERC20Validator.validateERC20Transfer.selector,
            configData: abi.encode(config)
        });
        // 2. Register config as governor
        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 3. Prepare invalid callData (transfer 50 tokens to user3 - not allowed)
        uint256 transferAmount = 50 ether;
        bytes memory callData = abi.encodeCall(IERC20.transfer, (user3, transferAmount));

        // 4. Validate - should revert
        vm.expectRevert(IERC20Validator.ERC20NotAllowed.selector);
        _validator.validate(tokenAddress, callData);
    }

    // --- Tests for validateAllowance ---

    function testValidateAllowanceSuccess() public {
        // 1. Config: Allow user1, user2 to be approved up to 1000 tokens
        address[] memory allowedSpenders = new address[](2);
        allowedSpenders[0] = user1;
        allowedSpenders[1] = user2;
        uint256 maxAmount = 1000 ether;
        IERC20Validator.ERC20AllowanceConfig memory config = IERC20Validator.ERC20AllowanceConfig({
            maxAmount: maxAmount,
            allowedSpenders: allowedSpenders
        });

        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = IValidator.ValidationRegistration({
            target: tokenAddress,
            externalSelector: IERC20.approve.selector,
            selfSelector: IERC20Validator.validateERC20Allowance.selector,
            configData: abi.encode(config)
        });
        // 2. Register config as governor
        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 3. Prepare valid callData (approve user1 for 500 tokens)
        uint256 approveAmount = 500 ether;
        bytes memory callData = abi.encodeCall(IERC20.approve, (user1, approveAmount));

        // 4. Validate - should succeed
        _validator.validate(tokenAddress, callData);
        assertTrue(true); // Explicit success assertion
    }

    function testValidateAllowanceRevertsAmountTooMuch() public {
        // 1. Config: Allow user1 to be approved up to 1000 tokens
        address[] memory allowedSpenders = new address[](1);
        allowedSpenders[0] = user1;
        uint256 maxAmount = 1000 ether;
        IERC20Validator.ERC20AllowanceConfig memory config = IERC20Validator.ERC20AllowanceConfig({
            maxAmount: maxAmount,
            allowedSpenders: allowedSpenders
        });

        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = IValidator.ValidationRegistration({
            target: tokenAddress,
            externalSelector: IERC20.approve.selector,
            selfSelector: IERC20Validator.validateERC20Allowance.selector,
            configData: abi.encode(config)
        });
        // 2. Register config as governor
        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 3. Prepare invalid callData (approve user1 for 1001 tokens)
        uint256 approveAmount = 1001 ether;
        bytes memory callData = abi.encodeCall(IERC20.approve, (user1, approveAmount));

        // 4. Validate - should revert
        vm.expectRevert(IERC20Validator.ERC20ApproveTooMuch.selector);
        _validator.validate(tokenAddress, callData);
    }

    function testValidateAllowanceRevertsSpenderNotAllowed() public {
        // 1. Config: Allow user1, user2 to be approved up to 1000 tokens
        address[] memory allowedSpenders = new address[](2);
        allowedSpenders[0] = user1;
        allowedSpenders[1] = user2;
        uint256 maxAmount = 1000 ether;
        IERC20Validator.ERC20AllowanceConfig memory config = IERC20Validator.ERC20AllowanceConfig({
            maxAmount: maxAmount,
            allowedSpenders: allowedSpenders
        });

        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = IValidator.ValidationRegistration({
            target: tokenAddress,
            externalSelector: IERC20.approve.selector,
            selfSelector: IERC20Validator.validateERC20Allowance.selector,
            configData: abi.encode(config)
        });
        // 2. Register config as governor
        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 3. Prepare invalid callData (approve user3 - not allowed - for 500 tokens)
        uint256 approveAmount = 500 ether;
        bytes memory callData = abi.encodeCall(IERC20.approve, (user3, approveAmount));

        // 4. Validate - should revert
        vm.expectRevert(IERC20Validator.ERC20NotAllowed.selector);
        _validator.validate(tokenAddress, callData);
    }
}
