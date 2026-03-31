// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ParachainStaking Interface
 * @dev Interface for Moonbeam's staking precompile with extended functionality
 */
interface IParachainStaking {
    // Events
    event JoinedCollatorCandidates(address indexed account, uint256 amount, uint256 newTotalAmountLocked);
    event CollatorChosen(uint32 indexed round, address indexed collatorAccount, uint256 totalExposed);
    event CandidateBondLessRequested(address indexed candidate, uint256 amountToDecrease, uint32 executionRound);
    event CandidateBondedMore(address indexed candidate, uint256 amount, uint256 newTotalBond);
    event CandidateBondedLess(address indexed candidate, uint256 amount, uint256 newBond);
    event CandidateWentOffline(uint32 indexed round, address indexed candidate);
    event CandidateBackOnline(uint32 indexed round, address indexed candidate);
    event CandidateScheduledExit(uint32 indexed round, address indexed candidate, uint32 scheduledExit);
    event CancelledCandidateExit(address indexed candidate);
    event CancelledCandidateBondLess(address indexed candidate, uint256 amount, uint32 round);
    event CandidateLeft(address indexed exCandidate, uint256 unlockedAmount, uint256 newTotalAmountLocked);
    event DelegationRequested(address indexed delegator, address indexed candidate, uint256 amount, uint32 round);
    event DelegatorExitScheduled(uint32 indexed round, address indexed delegator, uint32 scheduledExit);
    event DelegationExecuted(address indexed delegator, address indexed candidate, uint256 amount);
    event DelegatorBondedMore(address indexed delegator, address indexed candidate, uint256 amount, bool inTop);
    event DelegatorBondedLess(address indexed delegator, address indexed candidate, uint256 amount, bool inTop);
    event DelegatorLeft(address indexed delegator, uint256 unstakedAmount);
    event DelegationRevoked(address indexed delegator, address indexed candidate, uint256 amount);
    event DelegationIncreased(address indexed delegator, address indexed candidate, uint256 amount, bool inTop);
    event DelegationDecreased(address indexed delegator, address indexed candidate, uint256 amount, bool inTop);
    event AutoCompoundSet(address indexed delegator, address indexed candidate, uint8 value, uint256 delegatorAutoCompoundingDelegationCount);
    event AutoCompoundDelegatorRewardsPaid(address indexed candidate, address indexed delegator, uint256 amount);
    event Compounded(address indexed candidate, uint256 amount);
    event NewRound(uint32 indexed startingBlock, uint32 indexed round, uint32 selectedCollatorsNumber, uint256 totalBalance);
    event ReservedForParachainBond(address indexed account, uint256 value);
    event ParachainBondAccountSet(address indexed old, address indexed newAccount);
    event ParachainBondReservePercentSet(uint32 indexed old, uint32 indexed newPercent);
    event InflationSet(uint256 annualMin, uint256 annualIdeal, uint256 annualMax, uint256 roundMin, uint256 roundIdeal, uint256 roundMax);
    event StakeExpectationsSet(uint256 expectMin, uint256 expectIdeal, uint256 expectMax);
    event TotalSelectedSet(uint32 indexed old, uint32 indexed newTotal);
    event CollatorCommissionSet(uint32 indexed old, uint32 indexed newCommission);
    event BlocksPerRoundSet(uint32 indexed currentRound, uint32 indexed firstBlock, uint32 indexed old, uint32 newBlocks, uint32 newRoundFirst);
    event Rewarded(address indexed account, uint256 rewards);

    // Structs
    struct Bond {
        address owner;
        uint256 amount;
    }

    struct Nominator {
        address owner;
        uint256 amount;
    }

    struct CollatorSnapshot {
        uint256 bond;
        Nominator[] nominators;
        uint256 total;
    }

    struct Delegator {
        address owner;
        uint256 amount;
    }

    struct CandidateMetadata {
        uint256 bond;
        uint256 delegationCount;
        uint256 totalCounted;
        uint256 lowestTopDelegationAmount;
        uint256 highestBottomDelegationAmount;
        uint256 lowestBottomDelegationAmount;
        uint256 topCapacity;
        uint256 bottomCapacity;
        uint8 request;
        uint8 status;
    }

    struct DelegationDetails {
        address delegator;
        address candidate;
        uint256 amount;
        uint256 lessTotal;
        uint8 request;
    }

    struct DelayedPayout {
        uint32 roundIssuance;
        uint256 totalStakingReward;
        uint256 collatorCommission;
    }

    struct RoundInfo {
        uint32 current;
        uint32 first;
        uint256 length;
    }

    // View functions
    function isNominator(address nominator) external view returns (bool);
    function isCandidate(address candidate) external view returns (bool);
    function isSelectedCandidate(address candidate) external view returns (bool);
    function isDelegator(address delegator) external view returns (bool);
    function collatorNominationCount(address collator) external view returns (uint256);
    function nominatorNominationCount(address nominator) external view returns (uint256);
    function round() external view returns (uint32);
    function candidateCount() external view returns (uint256);
    function selectedCandidates() external view returns (address[] memory);
    function candidatePool() external view returns (address[] memory);
    function candidateDelegationCount(address candidate) external view returns (uint256);
    function delegatorDelegationCount(address delegator) external view returns (uint256);
    function delegationAmount(address delegator, address candidate) external view returns (uint256);
    function isInTopDelegations(address delegator, address candidate) external view returns (bool);
    function minDelegation() external view returns (uint256);
    function candidateAutoCompoundingDelegationCount(address candidate) external view returns (uint256);
    function delegationAutoCompound(address delegator, address candidate) external view returns (uint8);
    function candidateExitIsPending(address candidate) external view returns (bool);
    function candidateRequestIsPending(address candidate) external view returns (bool);
    function delegationRequestIsPending(address delegator, address candidate) external view returns (bool);
    function getCandidateInfo(address candidate) external view returns (CandidateMetadata memory);
    function getDelegationInfo(address delegator, address candidate) external view returns (DelegationDetails memory);
    function getCandidateTotalCounted(address candidate) external view returns (uint256);
    function getTopDelegations(address candidate) external view returns (Delegator[] memory);
    function getBottomDelegations(address candidate) external view returns (Delegator[] memory);
    function points(uint32 round) external view returns (uint256);
    function awardedPoints(uint32 round, address candidate) external view returns (uint256);

    // State-changing functions (made payable for testing purposes)
    function joinCandidates(uint256 amount, uint256 candidateCount) external payable;
    function scheduleLeaveCandidates(uint256 candidateCount) external;
    function executeLeaveCandidates(address candidate, uint256 candidateDelegationCount) external;
    function cancelLeaveCandidates(uint256 candidateCount) external;
    function goOffline() external;
    function goOnline() external;
    function candidateBondMore(uint256 more) external payable;
    function scheduleCandidateBondLess(uint256 less) external;
    function executeCandidateBondLess(address candidate) external;
    function cancelCandidateBondLess() external;
    function delegate(address candidate, uint256 amount, uint256 candidateDelegationCount, uint256 delegatorDelegationCount) external payable;
    function delegateWithAutoCompound(
        address candidate,
        uint256 amount,
        uint8 autoCompound,
        uint256 candidateDelegationCount,
        uint256 candidateAutoCompoundingDelegationCount,
        uint256 delegatorDelegationCount
    ) external payable;
    function scheduleRevokeDelegation(address candidate) external;
    function delegatorBondMore(address candidate, uint256 more) external payable;
    function scheduleDelegatorBondLess(address candidate, uint256 less) external;
    function executeDelegationRequest(address delegator, address candidate) external;
    function cancelDelegationRequest(address candidate) external;
    function setAutoCompound(
        address candidate,
        uint8 value,
        uint256 candidateAutoCompoundingDelegationCount,
        uint256 delegatorDelegationCount
    ) external;
}
