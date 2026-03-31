// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title The interface for the StellaSwap Voter
/// @dev Version: StellaSwap
interface IVoter {
  function getFeeDistributorForPool(address poolAddress) external view returns (address);
}
