// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface IIncentiveManager {
    function recordVote(uint256 amount, uint256 tokenId) external;
    function getReward(address recipient, uint256 tokenId, address[] memory tokens) external;
    function _withdraw(uint256 amount, uint256 tokenId) external;
    function calculateReward(address token, uint256 tokenId) external view returns (uint256);
    function notifyRewardAmount(address token, uint256 amount) external;
}
