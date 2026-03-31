// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../interfaces/ILedger.sol";
import "../interfaces/ILedgerTypes.sol";
import "../interfaces/IFundsManager.sol";
import "../interfaces/IAuthManager.sol";
import "../interfaces/Roles.sol";
import "../utils/TransferHelper.sol";
import "../interfaces/IParachainStaking.sol";

import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title Ledger
 * @notice Manages staking operations for individual collator candidates on Moonbeam
 * @dev This contract handles delegation, unbonding, and withdrawal operations for liquid staking.
 *      Each ledger is associated with a single collator candidate and manages the staking
 *      lifecycle including rewards distribution and chunk-based unbonding.
 *      
 */
contract Ledger is ILedger {
    using SafeCast for uint256;
    
    /// @notice Reference to the FundsManager contract
    IFundsManager public FUNDS_MANAGER;

    /// @notice The collator candidate this ledger delegates to
    address public CANDIDATE;
    
    /// @notice Current status of the ledger (None, Nominator, or Idle)
    LedgerTypes.LedgerStatus public status;
    
    /// @notice Moonbeam's parachain staking precompile interface
    IParachainStaking STAKING_PRECOMPILE;

    /// @notice Number of rounds to wait before unbonded funds can be withdrawn
    /// @dev This value is set during initialization from FundsManager (network-specific)
    uint8 public UNBOND_DELAY_ROUNDS;

    /// @notice Maximum number of unbonding chunks allowed (configurable)
    uint256 public MAX_UNLOCKING_CHUNKS;
    
    /// @notice Minimum balance required to be a nominator
    uint256 public MIN_NOMINATOR_BALANCE;


    /// @notice Array of all unbonding chunks for this ledger
    UnbondingChunk[] public unbondingChunks;
    
    /// @notice Cached delegation amount for reward calculation
    uint128 public cachedDelegationAmount;

    /// @notice Emitted when rewards are distributed from this ledger
    /// @param amount The amount of rewards distributed
    /// @param balance The total delegation balance after rewards
    event Rewards(uint128 amount, uint128 balance);
    
    /// @notice Emitted when GLMR is transferred to this ledger from FundsManager
    /// @param ledger The address of this ledger
    /// @param amount The amount transferred
    event TransferToLedger(address indexed ledger, uint128 amount);
    
    /// @notice Emitted when GLMR is transferred from this ledger to FundsManager
    /// @param ledger The address of this ledger
    /// @param amount The amount transferred
    event TransferFromLedger(address indexed ledger, uint128 amount);
    
    /// @notice Emitted when initial delegation is made to a validator
    /// @param ledger The address of this ledger
    /// @param amount The amount delegated
    event Bond(address indexed ledger, uint128 amount);
    
    /// @notice Emitted when additional delegation is made to increase existing stake
    /// @param ledger The address of this ledger
    /// @param amount The additional amount delegated
    event BondExtra(address indexed ledger, uint128 amount);
    
    /// @notice Emitted when delegation is scheduled for unbonding
    /// @param ledger The address of this ledger
    /// @param amount The amount scheduled for unbonding
    event Unbond(address indexed ledger, uint128 amount);
    
    /// @notice Emitted when unbonded funds are withdrawn from the validator
    /// @param ledger The address of this ledger
    /// @param amount The amount withdrawn
    event Withdraw(address indexed ledger, uint128 amount);
    
    /// @notice Emitted when unbonding is skipped due to chunk limit constraints
    /// @param ledger The address of this ledger
    /// @param amount The amount that should have been unbonded
    /// @param chunksSkipped The number of chunks that caused the skip
    event UnbondingSkipped(address indexed ledger, uint128 amount, uint256 chunksSkipped);
    
    /// @notice Emitted when the maximum unlocking chunks setting is updated
    /// @param newMaxChunks The new maximum number of chunks allowed
    event MaxUnlockingChunksUpdated(uint256 newMaxChunks);

    /**
     * @notice Restricts function access to the FundsManager contract only
     */
    modifier onlyFundsManager() {
        require(msg.sender == address(FUNDS_MANAGER), "LEDGER: NOT_FM");
        _;
    }

    /**
     * @notice Restricts function access to accounts with specific roles
     */
    modifier auth(bytes32 role) {
        require(IAuthManager(FUNDS_MANAGER.AUTH_MANAGER()).has(role, msg.sender), "LEDGER: UNAUTHORIZED");
        _;
    }

    /**
     * @notice Initialize the ledger with a funds manager
     * @param _fundsManager Address of the FundsManager contract
     * @dev Can only be called once during deployment. Sets up staking precompile
     *      and initial configuration parameters.
     */
    function initialize(address _fundsManager) public {
        require(address(FUNDS_MANAGER) == address(0), "LEDGER: ALREADY_INITIALIZED");
        status = LedgerTypes.LedgerStatus.None;

        MAX_UNLOCKING_CHUNKS = 1; // Currently limited to 1 chunk per ledger on Moonbeam
        STAKING_PRECOMPILE = IParachainStaking(0x0000000000000000000000000000000000000800);
        MIN_NOMINATOR_BALANCE = STAKING_PRECOMPILE.minDelegation();
        FUNDS_MANAGER = IFundsManager(_fundsManager);
        UNBOND_DELAY_ROUNDS = FUNDS_MANAGER.UNBOND_DELAY_ROUNDS();
    }

    /**
     * @notice Set the validator candidate for this ledger
     * @param _candidate Address of the validator candidate to delegate to
     * @dev Only callable by FundsManager
     */
    function setCandidate(address _candidate) external onlyFundsManager {
        require(CANDIDATE == address(0), "LEDGER: CANDIDATE_ALREADY_SET");
        CANDIDATE = _candidate;
    }

    /**
     * @notice Set the maximum number of unlocking chunks allowed
     * @param _maxChunks The new maximum number of unlocking chunks
     * @dev Only callable by FundsManager for security
     */
    function setMaxUnlockingChunks(uint256 _maxChunks) external onlyFundsManager {
        require(_maxChunks > 0 && _maxChunks <= 50, "LEDGER: INVALID_MAX_CHUNKS");
        MAX_UNLOCKING_CHUNKS = _maxChunks;
        emit MaxUnlockingChunksUpdated(_maxChunks);
    }

    /**
     * @notice Get the number of pending unbonding chunks
     * @return Number of unbonding chunks
     */
    function getPendingUnbondingChunks() external view returns (uint256) {
        return unbondingChunks.length;
    }

    /**
     * @notice Check if the ledger can safely perform unbonding without exceeding chunk limits
     * @return canUnbond True if unbonding is safe, false otherwise
     */
    function canSafelyUnbond() public view returns (bool canUnbond) {
        return unbondingChunks.length < MAX_UNLOCKING_CHUNKS;
    }

    /**
     * @notice Check if the ledger has any balance (delegated or free)
     * @return True if total balance is zero, false otherwise
     */
    function isEmpty() external view returns (bool) {
        return getTotalBalance() == 0;
    }

    /**
     * @notice Get the target stake amount allocated to this ledger by FundsManager
     * @return The amount of GLMR allocated to this ledger
     */
    function ledgerStake() public view override returns (uint256) {
        return FUNDS_MANAGER.ledgerStake(address(this));
    }

    /**
     * @notice Execute the main ledger operations including rewards distribution,
     *         bonding, unbonding, and withdrawals
     * @dev This is the primary function that synchronizes ledger state with
     *      the desired allocation from FundsManager. It handles:
     *      1. Reward distribution to FundsManager
     *      2. Transferring funds from FundsManager if needed
     *      3. Bonding additional funds or initial delegation
     *      4. Unbonding excess funds based on allocation changes
     *      5. Withdrawing matured unbonding chunks
     *      6. Transferring free balance back to FundsManager
     */
    function pushData() external auth(Roles.ROLE_REBALANCE_MANAGER) {
        // Important to distribute rewards first so ledgerStake is updated
        {
            uint128 _nowDelegationAmount = getDelegationAmount(); // active + unbonding amount
            uint128 _cachedDelegationAmount = cachedDelegationAmount;
            
            if (_cachedDelegationAmount < _nowDelegationAmount) {
                uint128 reward = _nowDelegationAmount - _cachedDelegationAmount;
                FUNDS_MANAGER.distributeRewards(reward, _nowDelegationAmount);
                emit Rewards(reward, _nowDelegationAmount);
            }
        }

        uint128 _activeBalance = getActiveAmount(); // currently generating rewards
        uint128 _ledgerStake = ledgerStake().toUint128(); // total amount of GLMR allocated to the ledger
        if (_activeBalance < _ledgerStake) { 
            // Fund Manager has allocated more GLMR
            uint128 deficit = _ledgerStake - _activeBalance;

            require(address(FUNDS_MANAGER).balance >= deficit, "LEDGER: TRANSFER_EXCEEDS_BALANCE");
            FUNDS_MANAGER.transferToLedger(deficit);
            emit TransferToLedger(address(this), deficit);
        }

        uint128 freeBalance = uint128(address(this).balance);

        if (_activeBalance < _ledgerStake) {
            // if ledger stake > active balance we are trying to bond all funds
            uint128 diff = _ledgerStake - _activeBalance;

            if (diff > 0 && freeBalance > 0) {
                uint128 diffToBond = diff > freeBalance ? freeBalance : diff;

                if (status == LedgerTypes.LedgerStatus.Nominator || status == LedgerTypes.LedgerStatus.Idle) {
                    STAKING_PRECOMPILE.delegatorBondMore(CANDIDATE, diffToBond);
                    emit BondExtra(address(this), diffToBond);

                } else if (status == LedgerTypes.LedgerStatus.None && diffToBond >= MIN_NOMINATOR_BALANCE) {

                    uint256 candidateDelegationCount = STAKING_PRECOMPILE.candidateDelegationCount(CANDIDATE);
                    uint256 delegatorDelegationCount = STAKING_PRECOMPILE.delegatorDelegationCount(address(this));
                    uint256 candidateAutoCompCount = STAKING_PRECOMPILE.candidateAutoCompoundingDelegationCount(CANDIDATE);

                    STAKING_PRECOMPILE.delegateWithAutoCompound(
                        CANDIDATE,
                        diffToBond, 
                        100, // 100%
                        candidateDelegationCount,
                        candidateAutoCompCount,
                        delegatorDelegationCount 
                    );
                    
                    status = LedgerTypes.LedgerStatus.Nominator;
                    
                    emit Bond(address(this), diffToBond);      
                } else revert("LEDGER: UNABLE_TO_BOND");
            }
        } else {
            // Fund Manager has reduced allocation so we need to unbond
            uint128 diff = _activeBalance - _ledgerStake;

            // Where we have to empty the ledger
            if (_ledgerStake < MIN_NOMINATOR_BALANCE && status != LedgerTypes.LedgerStatus.Idle && _activeBalance > 0) {
                // Check if we can safely unbond without exceeding the chunks limit
                if (canSafelyUnbond()) {
                    STAKING_PRECOMPILE.scheduleRevokeDelegation(CANDIDATE);
                    unbondingChunks.push(UnbondingChunk({
                        amount: _activeBalance,
                        requestRound: uint128(STAKING_PRECOMPILE.round())
                    }));

                    FUNDS_MANAGER.resetLedgerStake();

                    emit Unbond(address(this), _activeBalance);
                } else {
                    emit UnbondingSkipped(address(this), _activeBalance, unbondingChunks.length); // for offchain monitoring
                }
            } else if (diff > 0) {
                if (canSafelyUnbond()) {
                    STAKING_PRECOMPILE.scheduleDelegatorBondLess(CANDIDATE, diff);
                    unbondingChunks.push(UnbondingChunk({
                        amount: diff,
                        requestRound: uint128(STAKING_PRECOMPILE.round())
                    }));

                    emit Unbond(address(this), diff);
                } else {
                    emit UnbondingSkipped(address(this), diff, unbondingChunks.length); // for offchain monitoring
                }
            }
        }

        uint128 _withdrawAmount;
        uint256 chunksToRemove;
        (_withdrawAmount, chunksToRemove) = _getWithdrawableInfo();
        
        if (_withdrawAmount > 0) {
            STAKING_PRECOMPILE.executeDelegationRequest(address(this), CANDIDATE);
            
            // Remove processed chunks by shifting array
            for (uint256 i = chunksToRemove; i < unbondingChunks.length; i++) {
                unbondingChunks[i - chunksToRemove] = unbondingChunks[i];
            }
            
            // Reduce array length
            for (uint256 i = 0; i < chunksToRemove; i++) {
                unbondingChunks.pop();
            }

            if(getDelegationAmount() == 0) {
                status = LedgerTypes.LedgerStatus.None; // revoke needs new delegationWithAutoCompound
            }
            
            emit Withdraw(address(this), _withdrawAmount);
        }

        // After withdraw we get GLMR as free balance
        uint128 freeBalanceAfterWithdraw = uint128(address(this).balance);

        if (freeBalanceAfterWithdraw > 0) {
            uint128 principal = freeBalanceAfterWithdraw > _withdrawAmount
                ? _withdrawAmount
                : freeBalanceAfterWithdraw;

            // anything above principal is "extra" (rewards/dust)
            uint128 extra = freeBalanceAfterWithdraw - principal;

            TransferHelper.safeTransferETH(address(FUNDS_MANAGER), freeBalanceAfterWithdraw);
            FUNDS_MANAGER.transferFromLedger(principal, extra);

        }

        cachedDelegationAmount = getDelegationAmount();
    }
    /**
     * @notice Get withdrawable amount and count of mature chunks
     * @return withdrawableAmount Total amount ready for withdrawal
     * @return chunksToRemove Number of chunks ready for removal
     */
    function _getWithdrawableInfo() internal view returns (uint128 withdrawableAmount, uint256 chunksToRemove) {
        uint64 currentRound = uint64(STAKING_PRECOMPILE.round());
        for (uint256 i = 0; i < unbondingChunks.length; i++) {
            if (currentRound >= unbondingChunks[i].requestRound + UNBOND_DELAY_ROUNDS) {
                withdrawableAmount += unbondingChunks[i].amount;
                chunksToRemove++;
            } else {
                break;
            }
        }
    }

    /**
     * @notice Get total unlocking and withdrawable balances for external monitoring
     * @return unlockingBalance Total amount currently unbonding
     * @return withdrawableBalance Total amount ready for withdrawal
     */
    function getTotalUnlocking() external view returns (uint128 unlockingBalance, uint128 withdrawableBalance) {
        unlockingBalance = getTotalUnbondingAmount();
        (withdrawableBalance, ) = _getWithdrawableInfo();
    }

    /**
     * @notice Get total amount currently active (active + unbonding + free balance)
     * @return total Total active amount
     */
    function getTotalBalance() public view override returns (uint128) {
        return getDelegationAmount() + uint128(address(this).balance);
    }

    /**
     * @notice Get total amount currently active i.e making money
     * @return total Total active amount
     */
    function getActiveAmount() public view override returns (uint128) {
        return getDelegationAmount() - getTotalUnbondingAmount();
    }

    /**
     * @notice Get total amount currently unbonding across all chunks
     * @return total Total unbonding amount
     */
    function getTotalUnbondingAmount() public view override returns (uint128 total) {
        for (uint256 i = 0; i < unbondingChunks.length; i++) {
            total += unbondingChunks[i].amount;
        }
    }

    /**
     * @notice Get the number of current unbonding chunks
     * @return count Number of unbonding chunks
     */
    function getUnbondingChunksCount() external view returns (uint256 count) {
        return unbondingChunks.length;
    }

    /**
     * @notice Get details of a specific unbonding chunk
     * @param index Index of the chunk to retrieve
     * @return amount Amount in the chunk
     * @return requestRound Round when unbonding was requested
     */
    function getUnbondingChunk(uint256 index) external view returns (uint128 amount, uint128 requestRound) {
        require(index < unbondingChunks.length, "LEDGER: CHUNK_INDEX_OUT_OF_BOUNDS");
        UnbondingChunk memory chunk = unbondingChunks[index];
        return (chunk.amount, chunk.requestRound);
    }

    /**
     * @notice Get the delegation amount from blockchain (active + unbonding)
     * @return amount The amount of GLMR delegated to the candidate ( includes unbonidng amount)
     */
    function getDelegationAmount() public view override returns (uint128) {
        return uint128(STAKING_PRECOMPILE.delegationAmount(address(this), CANDIDATE));
    }


    /**
     * @notice Get the free transferable balance of the ledger
     * @return amount The amount of GLMR in the ledger
     */
    function getFreeBalance() public view override returns (uint128) {
        return uint128(address(this).balance);
    }

    receive() external payable {}
}
