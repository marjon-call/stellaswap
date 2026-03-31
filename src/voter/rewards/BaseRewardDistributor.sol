// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IVoting} from "../interfaces/IVoting.sol";
import {TimeLibrary} from "../libraries/Timelibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IIncentiveManagerFactory} from "../interfaces/IIncentiveManagerFactory.sol";
import {IVEStella} from "../interfaces/IVEStella.sol";

abstract contract BaseRewardDistributor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant DISTRIBUTION_PERIOD = 7 days;

    address public ve;
    address public votingContract;
    IIncentiveManagerFactory.RewardType public rewardType;

    uint256 public globalBalance;
    address public authorizedCaller;
    mapping(uint256 => uint256) public individualBalance;
    mapping(address => mapping(uint256 => uint256)) public epochRewardTokenAmounts;
    mapping(address => mapping(uint256 => uint256)) public lastClaimedTimestamp;
    address[] public rewardTokens;

    struct BalanceCheckpoint {
        uint256 checkpointTime;
        uint256 individualBalance;
    }

    struct GlobalCheckpoint {
        uint256 checkpointTime;
        uint256 globalBalance;
    }

    mapping(uint256 => mapping(uint256 => BalanceCheckpoint)) public balanceCheckpoints;
    mapping(uint256 => uint256) public checkpointCounts;
    mapping(uint256 => GlobalCheckpoint) public globalBalanceCheckpoints;
    uint256 public globalCheckpointCount;

    struct TokenReward {
        address token;
        uint256 amount;
    }

    event RewardNotification(address indexed notifier, address indexed token, uint256 epoch, uint256 amount);
    event TokensDeposited(address indexed user, uint256 indexed tokenId, uint256 amount);
    event TokensWithdrawn(address indexed user, uint256 indexed tokenId, uint256 amount);
    event RewardClaimed(address indexed recipient, address indexed token, uint256 reward);

    constructor(address _votingContract, address _authorizedCaller, IIncentiveManagerFactory.RewardType _rewardType) {
        votingContract = _votingContract;
        ve = IVoting(_votingContract).getVeStella();
        authorizedCaller = _authorizedCaller;
        rewardType = _rewardType;
    }

    function findPreviousBalanceIndex(uint256 tokenId, uint256 timestamp) public view returns (uint256) {
        uint256 nCheckpoints = checkpointCounts[tokenId];
        if (nCheckpoints == 0) {
            return 0;
        }

        if (balanceCheckpoints[tokenId][nCheckpoints - 1].checkpointTime <= timestamp) {
            return (nCheckpoints - 1);
        }

        if (balanceCheckpoints[tokenId][0].checkpointTime > timestamp) {
            return 0;
        }

        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2;
            BalanceCheckpoint memory cp = balanceCheckpoints[tokenId][center];
            if (cp.checkpointTime == timestamp) {
                return center;
            } else if (cp.checkpointTime < timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    function findPreviousGlobalIndex(uint256 timestamp) public view returns (uint256) {
        uint256 nCheckpoints = globalCheckpointCount;
        if (nCheckpoints == 0) {
            return 0;
        }

        if (globalBalanceCheckpoints[nCheckpoints - 1].checkpointTime <= timestamp) {
            return (nCheckpoints - 1);
        }

        if (globalBalanceCheckpoints[0].checkpointTime > timestamp) {
            return 0;
        }

        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2;
            GlobalCheckpoint memory cp = globalBalanceCheckpoints[center];
            if (cp.checkpointTime == timestamp) {
                return center;
            } else if (cp.checkpointTime < timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    function _logCheckpoint(uint256 tokenId, uint256 balance) internal {
        uint256 nCheckpoints = checkpointCounts[tokenId];
        uint256 timestamp = block.timestamp;

        if (
            nCheckpoints > 0
                && TimeLibrary.epochStart(balanceCheckpoints[tokenId][nCheckpoints - 1].checkpointTime)
                    == TimeLibrary.epochStart(timestamp)
        ) {
            balanceCheckpoints[tokenId][nCheckpoints - 1] = BalanceCheckpoint(timestamp, balance);
        } else {
            balanceCheckpoints[tokenId][nCheckpoints] = BalanceCheckpoint(timestamp, balance);
            checkpointCounts[tokenId] = nCheckpoints + 1;
        }
    }

    function _logGlobalCheckpoint() internal {
        uint256 nCheckpoints = globalCheckpointCount;
        uint256 timestamp = block.timestamp;

        if (
            nCheckpoints > 0
                && TimeLibrary.epochStart(globalBalanceCheckpoints[nCheckpoints - 1].checkpointTime)
                    == TimeLibrary.epochStart(timestamp)
        ) {
            globalBalanceCheckpoints[nCheckpoints - 1] = GlobalCheckpoint(timestamp, globalBalance);
        } else {
            globalBalanceCheckpoints[nCheckpoints] = GlobalCheckpoint(timestamp, globalBalance);
            globalCheckpointCount = nCheckpoints + 1;
        }
    }

    function recordVote(uint256 amount, uint256 tokenId) external {
        require(msg.sender == authorizedCaller, "Unauthorized");
        globalBalance += amount;
        individualBalance[tokenId] += amount;

        _logCheckpoint(tokenId, individualBalance[tokenId]);
        _logGlobalCheckpoint();

        emit TokensDeposited(msg.sender, tokenId, amount);
    }

    function _withdraw(uint256 amount, uint256 tokenId) external {
        require(msg.sender == authorizedCaller, "Unauthorized");
        globalBalance -= amount;
        individualBalance[tokenId] -= amount;

        _logCheckpoint(tokenId, individualBalance[tokenId]);
        _logGlobalCheckpoint();

        emit TokensWithdrawn(msg.sender, tokenId, amount);
    }

    function _notifyRewardAmount(address token, uint256 amount) internal virtual {
        require(amount != 0, "Invalid amount zero");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 currentEpoch = TimeLibrary.epochStart(block.timestamp);
        epochRewardTokenAmounts[token][currentEpoch] += amount;

        bool tokenExists = false;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == token) {
                tokenExists = true;
                break;
            }
        }
        if (!tokenExists) {
            rewardTokens.push(token);
        }

        emit RewardNotification(msg.sender, token, currentEpoch, amount);
    }

    function getReward(address recipient, uint256 tokenId, address[] memory tokens) external {
        if (rewardType != IIncentiveManagerFactory.RewardType.FREE_REWARDS) {
            require(msg.sender == authorizedCaller, "Unauthorized");
        } else {
            require(IVEStella(ve).isApprovedOrOwner(recipient, tokenId), "Not owner");
        }
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 rewardAmount = calculateReward(tokens[i], tokenId);
            lastClaimedTimestamp[tokens[i]][tokenId] = block.timestamp;
            if (rewardAmount > 0) IERC20(tokens[i]).safeTransfer(recipient, rewardAmount);

            emit RewardClaimed(recipient, tokens[i], rewardAmount);
        }
    }

    function calculateReward(address token, uint256 tokenId) public view returns (uint256) {
        if (checkpointCounts[tokenId] == 0) {
            return 0;
        }

        uint256 totalReward = 0;
        uint256 totalSupply = 1;
        uint256 startTime = TimeLibrary.epochStart(lastClaimedTimestamp[token][tokenId]);
        uint256 index = findPreviousBalanceIndex(tokenId, startTime);
        BalanceCheckpoint memory cp0 = balanceCheckpoints[tokenId][index];

        startTime = Math.max(startTime, TimeLibrary.epochStart(cp0.checkpointTime));

        uint256 epochCount = (TimeLibrary.epochStart(block.timestamp) - startTime) / DISTRIBUTION_PERIOD;

        if (epochCount > 0) {
            for (uint256 i = 0; i < epochCount; i++) {
                index = findPreviousBalanceIndex(tokenId, startTime + DISTRIBUTION_PERIOD - 1);
                cp0 = balanceCheckpoints[tokenId][index];
                totalSupply = Math.max(
                    globalBalanceCheckpoints[findPreviousGlobalIndex(startTime + DISTRIBUTION_PERIOD - 1)].globalBalance,
                    1
                );
                totalReward += (cp0.individualBalance * epochRewardTokenAmounts[token][startTime]) / totalSupply;
                startTime += DISTRIBUTION_PERIOD;
            }
        }

        return totalReward;
    }

    function getTotalRewards(uint256 tokenId) public view returns (TokenReward[] memory) {
        TokenReward[] memory rewards = new TokenReward[](rewardTokens.length);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 rewardAmount = calculateReward(token, tokenId);
            rewards[i] = TokenReward({token: token, amount: rewardAmount});
        }

        return rewards;
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function getEstimatedRewards(address token, uint256 tokenId) public view returns (uint256) {
        if (checkpointCounts[tokenId] == 0) {
            return 0;
        }

        // First calculate claimable rewards from completed epochs
        uint256 totalReward = calculateReward(token, tokenId);
        
        // Now add the pending reward from current epoch
        uint256 startTime = TimeLibrary.epochStart(block.timestamp);
        uint256 index = findPreviousBalanceIndex(tokenId, startTime);
        BalanceCheckpoint memory cp = balanceCheckpoints[tokenId][index];
        
        uint256 totalSupply = Math.max(
            globalBalanceCheckpoints[findPreviousGlobalIndex(startTime)].globalBalance,
            1
        );
        
        // Add the current epoch's pending rewards
        totalReward += (cp.individualBalance * epochRewardTokenAmounts[token][startTime]) / totalSupply;
        
        return totalReward;
    }

    function getEstimatedTotalRewards(uint256 tokenId) public view returns (TokenReward[] memory) {
        TokenReward[] memory rewards = new TokenReward[](rewardTokens.length);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 rewardAmount = getEstimatedRewards(token, tokenId);
            rewards[i] = TokenReward({token: token, amount: rewardAmount});
        }

        return rewards;
    }
}
