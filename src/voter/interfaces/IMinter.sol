// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
interface IMinter {
    function setWeekly(uint256 _weekly) external;
    function mintForEpoch() external;
}
