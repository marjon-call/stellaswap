// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title The interface for the StellaSwap Incentive Manager
/// @dev Version: StellaSwap
interface IIncentiveManager {
  function notifyRewardAmount(address token, uint256 amount) external;
}
