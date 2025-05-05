// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

import { AccessControl } from '@openzeppelin/contracts/access/AccessControl.sol';
import { SafeCast } from '@openzeppelin/contracts/utils/math/SafeCast.sol';

import { IOracle, IOracleAdapter } from 'src/interfaces/IOracle.sol';

contract BridgeOracle is IOracleAdapter, AccessControl {
    using SafeCast for uint256;

    bytes32 public constant GOVERNANCE_ROLE = keccak256('GOVERNANCE_ROLE');
    bytes32 public constant GUARDIAN_ROLE = keccak256('GUARDIAN_ROLE');

    address public baseUsdOracle;
    address public quoteUsdOracle;
    address public sequencerUptimeOracle;
    bool private isL2;
    uint64 public baseOracleTimeLimit;
    uint64 public quoteOracleTimeLimit;
    uint64 public sequencerDowntimeLimit;
    string public name; // We don't allow changing the name of this oracle to prevent inconsistency
    uint8 public constant decimals = 18;
    /// Some chains have not had sequencer uptime feed contract yet
    /// So that there will be an off-chain keeper to check sequencer status and set that status to this variable
    bool public isSequencerDown;

    /// Some chains have not had sequencer uptime feed contract yet
    /// So that there will be an off-chain keeper to check sequencer status and set startedAt to this variable
    uint256 public sequencerStartedAt;

    event OracleSet(string oracleType, address _oracleAddress);
    event OracleTimeLimitSet(string oracleType, uint64 _timeLimit);
    event SequencerStatusUpdated(bool isDown, uint256 startedAt);
    event SkipCheckStartedAtSet(bool value);

    error BadSetup();
    error PriceFeed();
    error SequencerDown();

    constructor(
        address _baseUsdOracle,
        address _quoteUsdOracle,
        address _sequencerUptimeOracle,
        uint64 _baseOracleTimeLimit,
        uint64 _quoteOracleTimeLimit,
        uint64 _sequencerDowntimeLimit,
        bool _isL2,
        string memory _name,
        address governor
    ) {
        if (_baseUsdOracle == address(0) || _quoteUsdOracle == address(0) || governor == address(0)) {
            revert BadSetup();
        }
        baseUsdOracle = _baseUsdOracle;
        quoteUsdOracle = _quoteUsdOracle;
        sequencerUptimeOracle = _sequencerUptimeOracle;
        baseOracleTimeLimit = _baseOracleTimeLimit;
        quoteOracleTimeLimit = _quoteOracleTimeLimit;
        sequencerDowntimeLimit = _sequencerDowntimeLimit;
        isL2 = _isL2;
        name = _name;
        isSequencerDown = true;
        _setRoleAdmin(GOVERNANCE_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(GUARDIAN_ROLE, GOVERNANCE_ROLE);
        _grantRole(GOVERNANCE_ROLE, governor);
        _grantRole(GUARDIAN_ROLE, governor);
    }

    /// @notice Sets the baseUsdOracle
    /// @param _baseUsdOracle The new address of baseUsdOracle
    /// @dev This function sets the address of baseUsdOracle oracle
    function setBaseUsdOracle(address _baseUsdOracle) external onlyRole(GOVERNANCE_ROLE) {
        baseUsdOracle = _baseUsdOracle;
        emit OracleSet('baseUsdOracle', _baseUsdOracle);
    }

    /// @notice Sets the quoteUsdOracle
    /// @param _quoteUsdOracle The new address of quoteUsdOracle
    /// @dev This function sets the address of quoteUsdOracle oracle
    function setQuoteUsdOracle(address _quoteUsdOracle) external onlyRole(GOVERNANCE_ROLE) {
        quoteUsdOracle = _quoteUsdOracle;
        emit OracleSet('quoteUsdOracle', _quoteUsdOracle);
    }

    /// @notice Sets the sequencerUptimeOracle
    /// @param _sequencerUptimeOracle The new address of _sequencerUptimeOracle
    /// @dev This function sets the address of sequencerUptimeOracle oracle
    function setSequencerUptimeOracle(address _sequencerUptimeOracle) external onlyRole(GOVERNANCE_ROLE) {
        sequencerUptimeOracle = _sequencerUptimeOracle;
        emit OracleSet('sequencerUptimeOracle', _sequencerUptimeOracle);
    }

    /// @notice Sets the baseOracleTimeLimit
    /// @param _baseOracleTimeLimit The new value of baseOracleTimeLimit
    /// @dev This function sets the value of baseOracleTimeLimit
    function setBaseOracleTimeLimit(uint64 _baseOracleTimeLimit) external onlyRole(GOVERNANCE_ROLE) {
        baseOracleTimeLimit = _baseOracleTimeLimit;
        emit OracleTimeLimitSet('baseOracleTimeLimit', _baseOracleTimeLimit);
    }

    /// @notice Sets the sequencerDowntimeLimit
    /// @param _sequencerDowntimeLimit The new value of sequencerDowntimeLimit
    /// @dev This function sets the value of sequencerDowntimeLimit
    function setSequencerDowntimeLimit(uint64 _sequencerDowntimeLimit) external onlyRole(GOVERNANCE_ROLE) {
        sequencerDowntimeLimit = _sequencerDowntimeLimit;
        emit OracleTimeLimitSet('sequencerDowntimeLimit', _sequencerDowntimeLimit);
    }

    /// @notice Sets the quoteOracleTimeLimit
    /// @param _quoteOracleTimeLimit The new value of quoteOracleTimeLimit
    /// @dev This function sets the value of quoteOracleTimeLimit
    function setQuoteOracleTimeLimit(uint64 _quoteOracleTimeLimit) external onlyRole(GOVERNANCE_ROLE) {
        quoteOracleTimeLimit = _quoteOracleTimeLimit;
        emit OracleTimeLimitSet('quoteOracleTimeLimit', _quoteOracleTimeLimit);
    }

    /// @notice Some chains have not had sequencer uptime feed contract yet
    ///         This function will be used by an off-chain keeper for setting isSequencerDown to mark sequencer status as down
    /// @param isDown The new value of isSequencerDown
    /// @param startedAt The new value of sequencerStartedAt
    function updateSequencerStatus(bool isDown, uint256 startedAt) external onlyRole(GUARDIAN_ROLE) {
        isSequencerDown = isDown;
        sequencerStartedAt = startedAt;
        emit SequencerStatusUpdated(isDown, startedAt);
    }

    function latestAnswer() external view returns (int256) {
        _checkSequencerDowntime();

        IOracle _quoteUsdOracle = IOracle(quoteUsdOracle);
        (, int256 quoteOraclePrice, , uint256 quoteUpdatedAt, ) = _quoteUsdOracle.latestRoundData();
        if (quoteOraclePrice <= 0 || quoteUpdatedAt + quoteOracleTimeLimit <= block.timestamp) revert PriceFeed();
        uint8 quoteOracleDecimals = _quoteUsdOracle.decimals();

        IOracle _baseUsdOracle = IOracle(baseUsdOracle);
        (, int256 baseOraclePrice, , uint256 baseUpdatedAt, ) = _baseUsdOracle.latestRoundData();
        if (baseOraclePrice <= 0 || baseUpdatedAt + baseOracleTimeLimit <= block.timestamp) revert PriceFeed();
        uint8 baseOracleDecimals = _baseUsdOracle.decimals();

        return
            (baseOraclePrice * (10 ** (quoteOracleDecimals + decimals)).toInt256()) /
            (quoteOraclePrice * (10 ** baseOracleDecimals).toInt256());
    }

    function _checkSequencerDowntime() internal view {
        if (!isL2) return;

        // there's no sequencer uptime oracle contract
        uint256 startedAt;
        if (sequencerUptimeOracle == address(0)) {
            if (isSequencerDown) revert SequencerDown();
            startedAt = sequencerStartedAt;
        } else {
            // check sequencer downtime via sequencer uptime oracle contract
            int256 answer;
            (, answer, startedAt, , ) = IOracle(sequencerUptimeOracle).latestRoundData();

            // ref: https://codehawks.cyfrin.io/c/2024-07-zaros/s/189 for checking startedAt != 0
            bool isSequencerUp = answer == 0 && startedAt != 0;

            if (!isSequencerUp) {
                revert SequencerDown();
            }
        }

        // Make sure the grace period has passed after the
        // sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= sequencerDowntimeLimit) {
            revert SequencerDown();
        }
    }
}
