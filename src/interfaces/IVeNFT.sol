// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Interface for verifying contract-based account signatures
/// @notice Interface that verifies provided signature for the data
/// @dev Interface defined by EIP-1271
interface IVeNFT {
    struct UserPoint {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts; // timestamp
        uint256 blk; // block number
        uint256 permanent;
    }

    struct EpochPoint {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts; // timestamp
        uint256 blk; // block
        uint256 permanentLockBalance;
    }

    struct LockedBalance {
        int128 amount;
        uint256 end;
        bool isPermanent;
    }

    struct Checkpoint {
        uint timestamp;
        uint[] tokenIds;
    }


    /// NORMAL  - typical veNFT
    /// MANAGED  - veNFT which is locked into a MANAGED veNFT
    /// MNFT - veNFT which can accept the deposit of NORMAL veNFTs
    enum LockType {
        NORMAL,
        MANAGED,
        MNFT
    }
}
