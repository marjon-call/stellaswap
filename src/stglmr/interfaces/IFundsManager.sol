// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ILedgerTypes.sol";

interface IFundsManager {
    function glmrAUM() external view returns(uint256);
    function deposit() external payable;
    function redeem(address _user, uint256 _amount) external;
    function claim(address _user) external;
    function ledgerStake(address ledger) external view returns (uint256);
    function resetLedgerStake() external;
    function transferFromLedger(uint256 _amount, uint256 _extra) external;
    function transferToLedger(uint256 amount) external;
    function distributeRewards(uint256 totalRewards, uint256 ledgerBalance) external;
    function AUTH_MANAGER() external returns(address);
    function getLedgerAddresses() external view returns (address[] memory);
    function rebalanceLedgerStakes() external;
    function UNBOND_DELAY_ROUNDS() external view returns (uint8);
}
