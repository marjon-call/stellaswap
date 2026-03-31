// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILedgerFactory {
    function createLedger() external returns (address);
}
