// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IValidator {
    enum Protocol {
        Velodrome,
        Thena,
        Shadow
    }

    struct ValidationConfig {
        bytes4 selfSelector;
        bytes configData;
    }

    struct ValidationRegistration {
        address target;
        bytes4 externalSelector;
        bytes4 selfSelector;
        bytes configData;
    }

    error TargetNotAllowed();
    error NoOracle();
    error OraclePairOrder();

    // Errors for helper checks
    error PriceDeviationExceeded();
    error SlippageExceeded();
    error SlippageTooHigh();

    // Other common errors (will be added later as needed)
    error InvalidRecipient();
    error PositionsCallFailed();
    error ValidationNotConfigured();
}
