// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { ValidatorTestBase } from './ValidatorTestBase.sol';
import { Validator } from 'src/Validator.sol';
import { IValidator } from 'src/interfaces/IValidator.sol';
import { IAccessControl } from '@openzeppelin/contracts/access/IAccessControl.sol';
// Potentially needed later: import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract ValidatorTest is ValidatorTestBase {
    function testInitializeSetsRoles() public {
        assertTrue(_validator.hasRole(_validator.DEFAULT_ADMIN_ROLE(), _governor), 'Governor should have admin role');
        assertTrue(_validator.hasRole(_validator.GOVERNANCE_ROLE(), _governor), 'Governor should have governance role');
        assertEq(
            _validator.getRoleAdmin(_validator.GOVERNANCE_ROLE()),
            _validator.GOVERNANCE_ROLE(),
            'Governance role admin should be itself'
        );
    }

    function testInitializeRevertsIfCalledAgain() public {
        bytes memory expectedError = abi.encodeWithSignature('InvalidInitialization()');
        vm.expectRevert(expectedError);
        _validator.initialize(_governor); // Try initializing again
    }

    function testRegisterValidationsSuccess() public {
        // Prepare registration data
        address targetContract = address(0xCAFE);
        bytes4 externalSel = bytes4(keccak256('externalFunction(uint256)'));
        bytes4 selfSel = bytes4(keccak256('internalValidation(address,bytes,bytes)')); // Dummy selector
        bytes memory configD = abi.encode(uint256(123), true);

        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = IValidator.ValidationRegistration({
            target: targetContract,
            externalSelector: externalSel,
            selfSelector: selfSel,
            configData: configD
        });

        // Register as governor
        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // Verify using the getter
        Validator.ValidationConfig memory retrievedConfig = _validator.getValidationConfig(targetContract, externalSel);

        assertEq(retrievedConfig.selfSelector, selfSel, 'Self selector mismatch');
        assertEq(retrievedConfig.configData, configD, 'Config data mismatch');
    }

    function testRegisterValidationsRevertsForNonGovernor() public {
        // Prepare registration data
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = IValidator.ValidationRegistration({
            target: address(0xBEEF),
            externalSelector: bytes4(keccak256('anotherExternal(address)')),
            selfSelector: bytes4(keccak256('anotherInternal(address,bytes,bytes)')),
            configData: abi.encode('test')
        });

        // Expect revert for non-governor
        bytes32 governanceRole = _validator.GOVERNANCE_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _nonGovernor,
                governanceRole
            )
        );

        vm.prank(_nonGovernor);
        _validator.registerValidations(registrations);
    }

    function testRegisterMultipleValidations() public {
        // Prepare registration data 1
        address target1 = address(0xABBA);
        bytes4 externalSel1 = bytes4(keccak256('func1()'));
        bytes4 selfSel1 = bytes4(keccak256('val1(address,bytes,bytes)'));
        bytes memory configD1 = abi.encode(uint8(1));

        // Prepare registration data 2
        address target2 = address(0xDEAF);
        bytes4 externalSel2 = bytes4(keccak256('func2(bool)'));
        bytes4 selfSel2 = bytes4(keccak256('val2(address,bytes,bytes)'));
        bytes memory configD2 = abi.encode(false);

        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](2);
        registrations[0] = IValidator.ValidationRegistration({
            target: target1,
            externalSelector: externalSel1,
            selfSelector: selfSel1,
            configData: configD1
        });
        registrations[1] = IValidator.ValidationRegistration({
            target: target2,
            externalSelector: externalSel2,
            selfSelector: selfSel2,
            configData: configD2
        });

        // Register as governor
        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // Verify registration 1
        Validator.ValidationConfig memory config1 = _validator.getValidationConfig(target1, externalSel1);
        assertEq(config1.selfSelector, selfSel1, 'Self selector 1 mismatch');
        assertEq(config1.configData, configD1, 'Config data 1 mismatch');

        // Verify registration 2
        Validator.ValidationConfig memory config2 = _validator.getValidationConfig(target2, externalSel2);
        assertEq(config2.selfSelector, selfSel2, 'Self selector 2 mismatch');
        assertEq(config2.configData, configD2, 'Config data 2 mismatch');
    }

    function testValidateRevertsIfNotConfigured() public {
        address unregisteredTarget = address(0xBAD);
        bytes4 unregisteredSelector = bytes4(0xdeadbeef);
        bytes memory dummyData = abi.encode(uint256(1));
        bytes memory callData = abi.encodePacked(unregisteredSelector, dummyData);

        // Expect revert because no validation is configured for this target/selector
        vm.expectRevert(ValidationNotConfigured.selector);
        _validator.validate(unregisteredTarget, callData);
    }

    function testValidateDispatchesSuccessfully() public {
        // 1. Define parameters for registration
        address targetContract = address(0x123);
        bytes4 externalSel = bytes4(keccak256('dispatchMe(uint256)'));
        bytes4 selfSel = bytes4(0xaaaaaaaa); // Arbitrary selector, won't be called
        bytes memory configD = abi.encode('config for dispatch');

        // 2. Register the validation rule
        IValidator.ValidationRegistration[] memory registrations = new IValidator.ValidationRegistration[](1);
        registrations[0] = IValidator.ValidationRegistration({
            target: targetContract,
            externalSelector: externalSel,
            selfSelector: selfSel,
            configData: configD
        });
        vm.prank(_governor);
        _validator.registerValidations(registrations);

        // 3. Prepare expected internal call data and mock the call
        bytes memory externalData = abi.encode(uint256(999));
        bytes memory internalCallData = abi.encodeWithSelector(selfSel, targetContract, externalData, configD);
        vm.mockCall(address(_validator), internalCallData, bytes(''));

        // 4. Prepare original callData for the validate function
        bytes memory originalCallData = abi.encodePacked(externalSel, externalData);

        // 5. Call validate - should dispatch internally, hit the mock, and succeed
        _validator.validate(targetContract, originalCallData);

        // 6. Assert success (optional, as no revert means success)
        assertTrue(true, 'Validation call should succeed');
    }
}
