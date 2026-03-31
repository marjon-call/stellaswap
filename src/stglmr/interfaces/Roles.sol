// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Roles {
    // Spec manager role
    bytes32 internal constant ROLE_SPEC_MANAGER = keccak256("ROLE_SPEC_MANAGER");

    bytes32 internal constant ROLE_PAUSE_MANAGER = keccak256("ROLE_PAUSE_MANAGER");

    bytes32 internal constant ROLE_REBALANCE_MANAGER = keccak256("ROLE_REBALANCE_MANAGER");
    // Beacon manager role
    bytes32 internal constant ROLE_BEACON_MANAGER = keccak256("ROLE_BEACON_MANAGER");

    // Ledger manager role
    bytes32 internal constant ROLE_LEDGER_MANAGER = keccak256("ROLE_LEDGER_MANAGER");

    // Fee manager role
    bytes32 internal constant ROLE_FEE_MANAGER = keccak256("ROLE_FEE_MANAGER");

    // Treasury manager role
    bytes32 internal constant ROLE_TREASURY = keccak256("ROLE_SET_TREASURY");

}
