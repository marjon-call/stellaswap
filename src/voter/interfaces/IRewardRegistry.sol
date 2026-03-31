// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IRewardRegistry {
    function getRewarderByPool(address poolAddress) external view returns (address);
}
