// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library veNFTErrors {
    error CallerDoesNotHaveRequiredRole();
    error ZeroAddress();
    error PercentageExceedsMax();
    error ValueCannotBeZero();
    error LockExpired();
    error NotApprovedOrOwner();
    error NotNormalNFT();
    error LockAmountTooLarge();
    error SplitAmountCannotBeZero();
    error CannotMergeSameNFT();
    error NotVoter();
    error NoOwner();
    error SplitNotAllowed();
    error LockExpiredOrPermanent();
    error InvalidSignature();
    error InvalidNonce();
    error SignatureExpired();
    error TooManyTokenIds();
    error LockDurationTooLong();
    error CanOnlyIncreaseLockDuration();
    error InvalidTokenId();
    error NotManagedNFT();
    error DstRepWouldHaveTooManyTokenIds();
    error SplitAmountTooLarge();
    error AlreadyVotedForNFT();
    error TokenNotDelegatedToYou();
    error GovernanceAlreadySet();
    error EmergencyWithdrawDisabled();
}
