// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ILedgerTypes.sol";

interface ILedger {
     /**
     * @notice Represents an unbonding chunk with amount and request round
     * @param amount The amount being unbonded
     * @param requestRound The round when unbonding was requested
     */
    struct UnbondingChunk {
        uint128 amount;
        uint128 requestRound;
    }

    // Management functions
    function initialize(address _fundsManager) external;
    function setCandidate(address _candidate) external;
    function setMaxUnlockingChunks(uint256 _maxChunks) external;
    
    // Core operations
    function pushData() external;
    
    // View functions - Status
    function isEmpty() external view returns (bool);
    function canSafelyUnbond() external view returns (bool);
    function ledgerStake() external view returns (uint256);
    
    // View functions - Balance queries
    function getTotalBalance() external view returns (uint128);
    function getActiveAmount() external view returns (uint128);
    function getDelegationAmount() external view returns (uint128);
    function getFreeBalance() external view returns (uint128);
    function getTotalUnbondingAmount() external view returns (uint128);
    
    // View functions - Unbonding chunks
    function getPendingUnbondingChunks() external view returns (uint256);
    function getUnbondingChunksCount() external view returns (uint256);
    function getUnbondingChunk(uint256 index) external view returns (uint128 amount, uint128 requestRound);
    function getTotalUnlocking() external view returns (uint128 unlockingBalance, uint128 withdrawableBalance);
}
