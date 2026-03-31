// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface IVEStella {
    enum LockType {
        NORMAL,
        MANAGED,
        MNFT
    }
    struct Checkpoint {
        uint256 fromBlock;
        uint256 votes;
    }

    struct LockedBalance {
        int128 amount;
        uint256 end;
        bool isPermanent;
    }
    struct ManagedNFT {
        address lockedReward;
        address freeReward;
    }

    struct ManagedInfo {
        uint256 mNFTId;
        uint256 weight;
    }

    function managedNFTRewards(uint256 managedTokenId)
        external
        view
        returns (address lockedReward, address freeReward);

    function managedInfo(uint256 tokenId) external view returns (ManagedInfo memory);
    function balanceOf(address account) external view returns (uint256);
    function balanceOfNFT(uint256 id) external view returns (uint256);
    function balanceOfNFTAt(uint256 id, uint256 timestamp) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalSupplyAt(uint256 timestamp) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool);
    function depositIntoManagedNFT(uint256 _tokenId, uint256 _managedTokenId) external;
    function withdrawFromManagedNFT(uint256 _tokenId) external;
    function lockType(uint256 _tokenId) external view returns (LockType);
    function increaseAmount(uint256 _tokenId, uint256 _value) external;

    function token() external view returns (address);
    function distributor() external view returns (address);
    function locked(uint256 _tokenId) external view returns (int128 amount, uint256 end, bool isPermanent);
}
