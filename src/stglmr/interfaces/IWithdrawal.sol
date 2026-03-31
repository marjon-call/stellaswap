// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWithdrawal {
    function totalVirtualGlmrAmount() external returns (uint256);

    function setFundsManager(address _fundsManager) external;

    function pendingForClaiming() external view returns (uint256);

    function newEra() external;

    function redeem(address _from, uint256 _amount) external;

    function claim(address _holder) external returns (uint256);

    function getRedeemStatus(address _holder) external view returns(uint256 _waiting, uint256 _available);
}
