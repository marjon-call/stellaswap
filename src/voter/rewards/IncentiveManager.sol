// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {BaseRewardDistributor} from "./BaseRewardDistributor.sol";
import {IVoting} from "../interfaces/IVoting.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IIncentiveManagerFactory} from "../interfaces/IIncentiveManagerFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IncentiveManager is BaseRewardDistributor, AccessControl {
    bytes32 public constant FEE_ADDER_ROLE = keccak256("FEE_ADDER_ROLE");

    IIncentiveManagerFactory.RewardType public RewardType;

    constructor(address _votingContract, address _deployer, IIncentiveManagerFactory.RewardType _rewardType, address _admin)
        BaseRewardDistributor(_votingContract, _deployer, _rewardType)
    {
        RewardType = _rewardType;
        votingContract = _votingContract;

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(FEE_ADDER_ROLE, _admin);
        _setupRole(FEE_ADDER_ROLE, _deployer);
        
    }

    function notifyRewardAmount(address token, uint256 amount) external {
        if (RewardType == IIncentiveManagerFactory.RewardType.BRIBE) {
            require(IVoting(votingContract).bribeWhiteListedRewardToken(token), "Bribe: Token not whitelisted");
        } else if (RewardType == IIncentiveManagerFactory.RewardType.FEE_SHARE) {
            require(hasRole(FEE_ADDER_ROLE, msg.sender), "Caller is not a fee adder");
        } else if (RewardType == IIncentiveManagerFactory.RewardType.LOCKED_REWARDS) {
            require(msg.sender == ve, "Only veStella can call");
        } else if (RewardType == IIncentiveManagerFactory.RewardType.FREE_REWARDS) {
            require(IVoting(votingContract).bribeWhiteListedRewardToken(token), "Free rewards: Token not whitelisted");
        }

        super._notifyRewardAmount(token, amount);
    }

    function changeAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function recoverERC20(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).transfer(msg.sender, amount);
    }

    function getTotalPendingRewards(uint256 tokenId) external view returns (TokenReward[] memory) {
        return getTotalRewards(tokenId);
    }
}
