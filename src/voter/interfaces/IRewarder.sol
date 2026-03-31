// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewarder {

    struct RewardInfo {
        IERC20 token;
        bool isNative;
        uint32 startTimestamp;
        uint32 endTimestamp;
        uint256 rewardPerSec;
    }
    
    function initialize(address _registry) external;
    function addRewardInfo(
        IERC20 token,
        bool _isNative,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        uint256 _rewardPerSec
    ) external payable;
    function getRoundedTimestamp(uint32 timestamp) external view returns (uint32);
    function getRewarderByPool(address pool) external view returns (address);
    function getActiveRewards() external view returns (RewardInfo[] memory);
}
