// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface LedgerTypes {
     enum LedgerStatus {
        // bonded but not participate in staking
        Idle,
        // participate as nominator
        Nominator,
        // not bonded not participate in staking
        None
    }

    struct UnlockingChunk {
        uint128 balance;
        uint64 round;
    }
}
