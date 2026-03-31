// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface IIncentiveManagerFactory {
    
    enum RewardType {
        BRIBE,
        FEE_SHARE,
        LOCKED_REWARDS,
        FREE_REWARDS
    }

    function createIncentiveManager(address _votingContract, address deployer, RewardType _rewardType, address _admin) external returns (address configDistributor);
}
