// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library VotingErrors {
    error NotApprovedOrOwner();
    error InvalidPool();
    error VotingNotStartedForEpoch();
    error EpochNotFinished();
    error PoolKilled();
    error PoolAlreadyRegistered();
    error PoolAlreadyKilled();
    error PoolAlreadyActive();
    error TokenNotAdded();
    error TokenNotInList();
    error TokenAlreadyAdded();
    error RewardAmountZero();
    error ArrayLengthMismatch();
    error ExceedingMaxVotes();
    error AlreadyVoted();
    error NoVoterWeight();
    error WeightCannotBeZero();
    error InvalidVotes();
    error OnlyOwnerOrEscrow();
    error VotingInCoolDown();
    error NoVotesInEpoch();
    error NotNormalNFT();
    error VotingNotStarted();
}
