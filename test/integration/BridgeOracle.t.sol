// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

import { AccessControl } from '@openzeppelin/contracts/access/AccessControl.sol';
import { SafeCast } from '@openzeppelin/contracts/utils/math/SafeCast.sol';

uint16 constant BASE = 10_000;
uint256 constant CURVE_MAP_SLOT = 65_551;
uint256 constant POOL_IDX = 420;
uint256 constant MAX_NUMBER_OF_WITHDRAWAL_SPLIT = 10;
bytes32 constant GOVERNANCE_ROLE = keccak256('GOVERNANCE');
bytes32 constant GUARDIAN_ROLE = keccak256('GUARDIAN');
uint256 constant DEAD_SHARES = 1_000;

string constant BAD_SETUP = 'B';
string constant PRICE_FEED = 'P';
string constant SEQUENCER_DOWN = 'SD';
interface IOracle {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint8);
}

contract BridgeOracle is AccessControl {
    using SafeCast for uint256;

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

    event OracleSet(string oracleType, address _oracleAddress);
    event OracleTimeLimitSet(string oracleType, uint64 _timeLimit);
    event IsSequencerDownSet(bool value);

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
            revert(BAD_SETUP);
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
    /// @param value The new value of isSequencerDown
    function setIsSequencerDown(bool value) external onlyRole(GUARDIAN_ROLE) {
        isSequencerDown = value;
        emit IsSequencerDownSet(value);
    }

    function latestAnswer() external view returns (int256) {
        _checkSequencerDowntime();

        IOracle _quoteUsdOracle = IOracle(quoteUsdOracle);
        (, int256 quoteOraclePrice, , uint256 quoteUpdatedAt, ) = _quoteUsdOracle.latestRoundData();
        if (quoteOraclePrice <= 0 || quoteUpdatedAt + quoteOracleTimeLimit <= block.timestamp) revert(PRICE_FEED);
        uint8 quoteOracleDecimals = _quoteUsdOracle.decimals();

        IOracle _baseUsdOracle = IOracle(baseUsdOracle);
        (, int256 baseOraclePrice, , uint256 baseUpdatedAt, ) = _baseUsdOracle.latestRoundData();
        if (baseOraclePrice <= 0 || baseUpdatedAt + baseOracleTimeLimit <= block.timestamp) revert(PRICE_FEED);
        uint8 baseOracleDecimals = _baseUsdOracle.decimals();

        return
            (quoteOraclePrice * (10 ** (decimals + baseOracleDecimals)).toInt256()) /
            (baseOraclePrice * (10 ** quoteOracleDecimals).toInt256());
    }

    function numeraireLatestAnswer() external view returns (int256) {
        _checkSequencerDowntime();

        IOracle _baseUsdOracle = IOracle(baseUsdOracle);
        (, int256 baseOraclePrice, , uint256 updatedAt, ) = _baseUsdOracle.latestRoundData();
        if (baseOraclePrice <= 0 || updatedAt + baseOracleTimeLimit <= block.timestamp) revert(PRICE_FEED);

        return (baseOraclePrice * (10 ** decimals).toInt256()) / (10 ** _baseUsdOracle.decimals()).toInt256();
    }

    function _checkSequencerDowntime() internal view {
        if (!isL2) return;

        // there's no sequencer uptime oracle contract
        if (sequencerUptimeOracle == address(0)) {
            if (isSequencerDown) revert(SEQUENCER_DOWN);
        } else {
            // check sequencer downtime via sequencer uptime oracle contract
            (, int256 answer, uint256 startedAt, , ) = IOracle(sequencerUptimeOracle).latestRoundData();

            // ref: https://codehawks.cyfrin.io/c/2024-07-zaros/s/189 for checking startedAt != 0
            bool isSequencerUp = answer == 0 && startedAt != 0;
            if (!isSequencerUp) {
                revert(SEQUENCER_DOWN);
            }

            // Make sure the grace period has passed after the
            // sequencer is back up.
            uint256 timeSinceUp = block.timestamp - startedAt;
            if (timeSinceUp <= sequencerDowntimeLimit) {
                revert(SEQUENCER_DOWN);
            }
        }
    }
}
