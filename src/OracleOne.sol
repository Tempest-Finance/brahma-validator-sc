// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

import { SafeCast } from '@openzeppelin/contracts/utils/math/SafeCast.sol';

import { IOracle } from 'src/interfaces/IOracle.sol';

contract OracleOne is IOracle {
    using SafeCast for uint256;

    string private _description;

    constructor(string memory _desc) {
        _description = _desc;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 0;
        answer = 1e18;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = 0;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function description() external view returns (string memory) {
        return _description;
    }
}
