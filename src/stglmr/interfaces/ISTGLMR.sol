// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISTGLMR {
    function deposit() external payable returns (uint256);
    
    function redeem(uint256 shares) external;
    
    function claimUnbonded() external;
    
    function mintSharesForReward(address to, uint256 _shares) external;
}
