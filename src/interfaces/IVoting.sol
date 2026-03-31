// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface IVoting {
    // View struct without mapping for external calls
    struct VoteCheckpoint {
        uint256 totalVotes;
        uint256 epoch;
        bool isVoting;
        address[] pools;
    }

    function getVeStella() external view returns (address);
    function bribeWhiteListedRewardToken(address _token) external view returns (bool);
    function claimBribes(address[] calldata _bribes, address[][] calldata _tokens, uint256 _tokenId) external;
    function claimFees(address[] calldata _fees, address[][] calldata _tokens, uint256 _tokenId) external;
    function vote(uint256 nftId, address[] memory _poolAddresses, uint256[] memory weights) external;
    function getPoolVotes(address poolAddress) external view returns (uint256);
    function nftVoteData(uint256 _tokenId) external view returns (VoteCheckpoint memory);
    function voted(uint256 _tokenId) external view returns (bool);
    function totalVotes() external view returns (uint256);
    function getPoolsVotedByNFTForEpoch(uint256 _nftId) external view returns (address[] memory);
    function getPoolVotesForNFT(uint256 nftId, address pool) external view returns (uint256);
    function reset(uint256 _tokenId) external;
}
