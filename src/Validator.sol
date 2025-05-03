// SPDX-License-Identifier: MIT

pragma solidity >=0.8.24;

import { ERC20Validator } from 'src/base/ERC20Validator.sol';
import { ShadowValidator } from 'src/base/ShadowValidator.sol';
import { VelodromeValidator } from 'src/base/VelodromeValidator.sol';
import { ThenaValidator } from 'src/base/ThenaValidator.sol';

import { Address } from '@openzeppelin/contracts/utils/Address.sol';
import { BytesLib } from 'src/libraries/BytesLib.sol';

import { AccessControlUpgradeable } from '@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol';

/**
 * @title Main Validator Contract
 * @notice Aggregates validation logic from various base contracts and dispatches calls.
 * @dev Upgradeable logic contract using AccessControlUpgradeable.
 */
contract Validator is AccessControlUpgradeable, ERC20Validator, ShadowValidator, VelodromeValidator, ThenaValidator {
    using Address for address;
    using BytesLib for bytes;

    bytes32 public constant GOVERNANCE_ROLE = keccak256('GOVERNANCE_ROLE');

    constructor() {
        _disableInitializers(); // Disable initializer function after deployment
    }

    /**
     * @notice Initializes the contract, setting state variables and access control roles.
     * @param governor Address to grant initial admin and governance roles.
     */
    function initialize(address governor) public initializer {
        __AccessControl_init();

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(GOVERNANCE_ROLE, governor);
        _setRoleAdmin(GOVERNANCE_ROLE, GOVERNANCE_ROLE);
    }

    /**
     * @notice Main validation entry point. Dispatches to specific validation logic.
     * @param target The address of the contract being interacted with.
     * @param callData The original call data for the interaction.
     */
    function validate(address target, bytes calldata callData) external {
        // Parse selector and remaining data
        (bytes4 selector, bytes memory data) = callData._popHeadSelector();

        // Retrieve validation configuration
        ValidationConfig memory config = _validationConfigs[_validationKey(target, selector)];

        // Ensure validation is configured for this target/selector
        require(config.selfSelector != bytes4(0), ValidationNotConfigured());

        // Dispatch to the configured public validation function
        // Use functionDelegateCall and let internal functions revert on failure
        address(this).functionDelegateCall(
            abi.encodeWithSelector(config.selfSelector, target, data, config.configData)
        );
    }

    /**
     * @notice Registers multiple validation configurations in batch.
     * @dev Requires caller to have the GOVERNANCE_ROLE.
     * @param registrations An array of validation rules to register.
     */
    function registerValidations(
        ValidationRegistration[] calldata registrations
    )
        external
        onlyRole(GOVERNANCE_ROLE) // Use AccessControl modifier
    {
        for (uint256 i = 0; i < registrations.length; i++) {
            ValidationRegistration calldata reg = registrations[i];
            _registerValidation(reg.target, reg.externalSelector, reg.selfSelector, reg.configData);
        }
    }

    /**
     * @notice Registers a new oracle for token pair
     * @dev Only callable by the GOVERNANCE_ROLE
     * @param token0 The address of the first token in the pair
     * @param token1 The address of the second token in the pair
     * @param adapter The address of the adapter contract
     */
    function registerOracle(address token0, address token1, address adapter) external onlyRole(GOVERNANCE_ROLE) {
        _registerOracle(token0, token1, adapter);
    }

    /**
     * @notice Retrieves the validation configuration for a specific target and external selector.
     * @param target The target contract address.
     * @param externalSelector The external function selector being validated.
     * @return config The stored ValidationConfig struct.
     */
    function getValidationConfig(
        address target,
        bytes4 externalSelector
    ) external view returns (ValidationConfig memory config) {
        config = _validationConfigs[_validationKey(target, externalSelector)];
    }

    /**
     * @notice Returns registered oracle of the pair
     * @param token0 The address of the first token in the pair
     * @param token1 The address of the second token in the pair
     */
    function getOracle(address token0, address token1) external view returns (address) {
        return _getOracle(token0, token1);
    }
}
