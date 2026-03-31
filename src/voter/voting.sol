// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {VotingErrors} from "./libraries/VotingErrors.sol";
import {IVEStella} from "./interfaces/IVEStella.sol";
import {IIncentiveManager} from "./interfaces/IIncentiveManager.sol";
import {IRewarder} from "./interfaces/IRewarder.sol";
import {IIncentiveManagerFactory} from "./interfaces/IIncentiveManagerFactory.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IRewardRegistry} from "./interfaces/IRewardRegistry.sol";
import {IncentiveManager} from "./rewards/IncentiveManager.sol";
import {IWGLMR} from "./interfaces/IWGLMR.sol";
import {TimeLibrary} from "./libraries/Timelibrary.sol";

contract Voting is 
    ReentrancyGuardUpgradeable, 
    AccessControlUpgradeable,
    UUPSUpgradeable 
{
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant EMERGENCY_COUNCIL_ROLE = keccak256("EMERGENCY_COUNCIL_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    IVEStella public veStellaToken;

    uint256 public MAX_VOTES_PER_EPOCH;
    uint256 public totalVotes; // Total votes across all pools
    uint256 public poolCount; // Total number of pools
    uint256 public epochDuration;
    uint256 public lastEpochTime;
    uint256 public COOL_DOWN_PERIOD;
    uint256 public processedPools;
    uint256 public startOfVoteEpoch;

    address public wrappedGLMR;
    address public rewardRegistryAddress;
    address public incentiveManagerFactory;
    address public minter;

    bool public emergencyPaused;

    struct Pool {
        uint256 totalVotes;
        bool isRegistered;
        address feeDistributor;
        address bribeDistributor;
    }

    struct VoteCheckpoint {
        uint256 totalVotes; // Total votes in a particular checkpoint (epoch)
        mapping(address => uint256) poolVotes;
        uint256 epoch;
        bool isVoting;
        address[] pools;
    }

    mapping(address => Pool) public pools; // poolAddress => Pool
    mapping(address => bool) public isAlive;
    mapping(uint256 => VoteCheckpoint) public nftVoteData; // Nft id to voteCHeckpoint

    // for distribute rewards
    mapping(uint256 => bool) public epochRewardDistributed;

    address[] public poolAddresses;

    address[] public rewardTokens;

    mapping(address => bool) public isRewardToken; // Tracking if a token is in use
    mapping(address => uint256) public epochRewards; // Reward allocated per epoch per token

    mapping(address => bool) public bribeWhiteListedRewardToken;
    address[] public bribeWhiteListedRewardTokenList;

    event VoteCast(uint256 indexed voterNft, address[] poolIds, uint256[] weights);
    event RewardsDistributed(uint256 epoch);
    event RewardsDistributedDetails(uint256 epoch, address poolAddress, address rewardAddress, uint256 rewards, uint256 poolVotes, uint256 totalVotes, uint256 poolPercentage);
    event RewardAllocated(address poolId, address token, uint256 reward);
    event RewardNotified(address[] tokens, uint256[] amounts);
    event AddWhitelistedBribeToken(address token);
    event RemoveWhitelistedBribeToken(address token);

    event RewardTokenAdded(address token);
    event RewardTokenRemoved(address token);
    event PoolRegistered(address poolAddress, address feeDistributor, address bribe);
    event PoolKilled(address poolAddress);
    event PoolRevived(address poolAddress);
    event MaxVotesPerEpochUpdated(uint256 _perEpoch);
    event CoolDownPeriodUpdated(uint256 _newCoolDownPeriod);

    modifier onlyDuringEpoch(uint256 _nftId) {
        uint256 currentEpoch = getCurrentEpoch();
        VoteCheckpoint storage voteData = nftVoteData[_nftId];
        if (voteData.epoch >= currentEpoch) {
            revert VotingErrors.AlreadyVoted();
        }

        if (
            block.timestamp <= TimeLibrary.epochStart(block.timestamp) + COOL_DOWN_PERIOD
                || block.timestamp >= TimeLibrary.epochNext(block.timestamp) - COOL_DOWN_PERIOD
        ) {
            revert VotingErrors.VotingInCoolDown();
        }
        _;
    }

    modifier ownerOrEscrow(uint256 _tokenId) {
        if (!veStellaToken.isApprovedOrOwner(msg.sender, _tokenId)) {
            revert VotingErrors.OnlyOwnerOrEscrow();
        }
        _;
    }

    modifier whenNotPaused() {
        require(!emergencyPaused, "Contract paused");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _veStellaToken,
        address _WGLMR,
        address _rewardRegistryAddress,
        address _incentiveManagerFactory,
        address _minter,
        address _admin
    ) public initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        require(_veStellaToken != address(0), "Zero address not allowed");
        require(_WGLMR != address(0), "Zero address not allowed");
        require(_rewardRegistryAddress != address(0), "Zero address not allowed");
        require(_incentiveManagerFactory != address(0), "Zero address not allowed");
        require(_minter != address(0), "Zero address not allowed");
        require(_admin != address(0), "Zero address not allowed");

        veStellaToken = IVEStella(_veStellaToken);
        wrappedGLMR = _WGLMR;
        rewardRegistryAddress = _rewardRegistryAddress;
        incentiveManagerFactory = _incentiveManagerFactory;
        minter = _minter;
        
        // Initialize default values
        MAX_VOTES_PER_EPOCH = 30;
        epochDuration = 1 weeks;
        COOL_DOWN_PERIOD = 1 hours;
        startOfVoteEpoch = 1751500800;
        emergencyPaused = false;
        lastEpochTime = block.timestamp / epochDuration; // Initialize lastEpochTime safely

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(EMERGENCY_COUNCIL_ROLE, _admin);
        _setupRole(ADMIN_ROLE, _admin);
        _setupRole(UPGRADER_ROLE, _admin);
        _setupRole(DISTRIBUTOR_ROLE, _admin);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    function setIncentiveManagerFactory(address _incentiveManagerFactory) external onlyRole(ADMIN_ROLE) {
        require(_incentiveManagerFactory != address(0), "Zero address not allowed");
        incentiveManagerFactory = _incentiveManagerFactory;
    }

    function setMinter(address _minter) external onlyRole(ADMIN_ROLE) {
        require(_minter != address(0), "Zero address not allowed");
        minter = _minter;
    }

    function setRewardRegistry(address _rewardRegistry) external onlyRole(ADMIN_ROLE) {
        require(_rewardRegistry != address(0), "Zero address not allowed");
        rewardRegistryAddress = _rewardRegistry;
    }

    function togglePause(bool _toggle) external onlyRole(ADMIN_ROLE) {
        emergencyPaused = _toggle;
    }

    function addRewardToken(address _token) external onlyRole(ADMIN_ROLE) {
        if (isRewardToken[_token]) {
            revert VotingErrors.TokenAlreadyAdded();
        }
        rewardTokens.push(_token);
        isRewardToken[_token] = true;
        emit RewardTokenAdded(_token);
    }

    function setStartOfVoteEpoch(uint256 _startOfVoteEpoch) external onlyRole(ADMIN_ROLE) {
        startOfVoteEpoch = _startOfVoteEpoch;
    }

    function addWhitelistedBribeToken(address _token) external onlyRole(ADMIN_ROLE) {
        if (bribeWhiteListedRewardToken[_token]) {
            revert VotingErrors.TokenAlreadyAdded();
        }
        bribeWhiteListedRewardToken[_token] = true;
        bribeWhiteListedRewardTokenList.push(_token);
        emit AddWhitelistedBribeToken(_token);
    }

    function removeWhitelistedBribeToken(address _token) external onlyRole(ADMIN_ROLE) {
        if (!bribeWhiteListedRewardToken[_token]) {
            revert VotingErrors.TokenNotInList();
        }
        bribeWhiteListedRewardToken[_token] = false;

        for (uint256 i = 0; i < bribeWhiteListedRewardTokenList.length; i++) {
            if (bribeWhiteListedRewardTokenList[i] == _token) {
                bribeWhiteListedRewardTokenList[i] =
                    bribeWhiteListedRewardTokenList[bribeWhiteListedRewardTokenList.length - 1];
                bribeWhiteListedRewardTokenList.pop();
                break;
            }
        }
        emit RemoveWhitelistedBribeToken(_token);
    }

    function removeRewardToken(address _token) external onlyRole(ADMIN_ROLE) {
        if (!isRewardToken[_token]) {
            revert VotingErrors.TokenNotInList();
        }
        isRewardToken[_token] = false;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == _token) {
                rewardTokens[i] = rewardTokens[rewardTokens.length - 1];
                rewardTokens.pop();
                break;
            }
        }

        emit RewardTokenRemoved(_token);
    }

    function setEpochRewards(address[] calldata _tokens, uint256[] calldata _rewards) external onlyRole(ADMIN_ROLE) {
        if (_tokens.length != _rewards.length) {
            revert VotingErrors.ArrayLengthMismatch();
        }
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (!isRewardToken[_tokens[i]]) {
                revert VotingErrors.TokenNotAdded();
            }
            epochRewards[_tokens[i]] = _rewards[i];
        }
    }

    function setCoolDownPeriod(uint256 _coolDownPeriod) external onlyRole(ADMIN_ROLE) {
        COOL_DOWN_PERIOD = _coolDownPeriod;
        emit CoolDownPeriodUpdated(_coolDownPeriod);
    }

    function notifyRewardAmount(address[] calldata _tokens, uint256[] calldata _amounts)
        external
        whenNotPaused
        nonReentrant
        onlyRole(ADMIN_ROLE)
    {
        if (_tokens.length != _amounts.length) {
            revert VotingErrors.ArrayLengthMismatch();
        }
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (!isRewardToken[_tokens[i]]) {
                revert VotingErrors.TokenNotAdded();
            }
            if (_amounts[i] <= 0) {
                revert VotingErrors.RewardAmountZero();
            }

            IERC20(_tokens[i]).transferFrom(msg.sender, address(this), _amounts[i]);
        }

        emit RewardNotified(_tokens, _amounts);
    }

    function killPool(address poolAddress) external onlyRole(EMERGENCY_COUNCIL_ROLE) {
        if (!isAlive[poolAddress]) {
            revert VotingErrors.PoolAlreadyKilled();
        }
        isAlive[poolAddress] = false;
        emit PoolKilled(poolAddress);
    }

    function revivePool(address poolAddress) external onlyRole(EMERGENCY_COUNCIL_ROLE) {
        if (isAlive[poolAddress]) {
            revert VotingErrors.PoolAlreadyActive();
        }
        isAlive[poolAddress] = true;
        emit PoolRevived(poolAddress);
    }

    function registerPool(address poolAddress) external onlyRole(ADMIN_ROLE) {
        if (pools[poolAddress].isRegistered) {
            revert VotingErrors.PoolAlreadyRegistered();
        }
        address newFeeDistributor = IIncentiveManagerFactory(incentiveManagerFactory).createIncentiveManager(
            address(this), address(this), IIncentiveManagerFactory.RewardType.FEE_SHARE, msg.sender
        );

        address newBribe = IIncentiveManagerFactory(incentiveManagerFactory).createIncentiveManager(
            address(this), address(this), IIncentiveManagerFactory.RewardType.BRIBE, msg.sender
        );

        pools[poolAddress] =
            Pool({totalVotes: 0, isRegistered: true, feeDistributor: newFeeDistributor, bribeDistributor: newBribe});

        poolAddresses.push(poolAddress);
        poolCount++;

        isAlive[poolAddress] = true;

        emit PoolRegistered(poolAddress, newFeeDistributor, newBribe);
    }

    function vote(uint256 nftId, address[] memory _poolAddresses, uint256[] memory weights)
        public
        onlyDuringEpoch(nftId)
        whenNotPaused
        nonReentrant
    {
        if (block.timestamp < startOfVoteEpoch) {
            revert VotingErrors.VotingNotStarted();
        }
        uint256 currentEpoch = getCurrentEpoch();

        // Check: Ensure the caller is approved or owns the NFT
        if (!veStellaToken.isApprovedOrOwner(msg.sender, nftId)) {
            revert VotingErrors.NotApprovedOrOwner();
        }

        // Check: Ensure arrays are of equal length
        if (_poolAddresses.length != weights.length) {
            revert VotingErrors.ArrayLengthMismatch();
        }

        // Check: Ensure maximum votes per epoch is not exceeded
        if (_poolAddresses.length > MAX_VOTES_PER_EPOCH) {
            revert VotingErrors.ExceedingMaxVotes();
        }

        // Check: Ensure NFT has voting weight
        uint256 voterWeight = veStellaToken.balanceOfNFT(nftId);
        if (voterWeight <= 0) {
            revert VotingErrors.NoVoterWeight();
        }

        // Check: Validate pool state and calculate total weight
        uint256 totalWeights = 0;
        for (uint256 i = 0; i < _poolAddresses.length; i++) {
            if (!isAlive[_poolAddresses[i]]) {
                revert VotingErrors.PoolKilled();
            }
            if (weights[i] <= 0) {
                revert VotingErrors.WeightCannotBeZero();
            }
            totalWeights += weights[i];
        }

        nftVoteData[nftId].epoch = currentEpoch;

        _vote(nftId, _poolAddresses, weights, voterWeight, totalWeights);
    }

    function _vote(
        uint256 nftId,
        address[] memory _poolAddresses,
        uint256[] memory weights,
        uint256 voterWeight,
        uint256 totalWeights
    ) internal {
        VoteCheckpoint storage voteData = nftVoteData[nftId];
        _reset(nftId);
        // Cast votes for each pool
        uint256 currentTotal = totalVotes;
        for (uint256 i = 0; i < _poolAddresses.length; i++) {
            address poolAddress = _poolAddresses[i];
            uint256 weight = (weights[i] * voterWeight) / totalWeights;

            // Record votes for fee and bribe distributors
            IIncentiveManager(pools[poolAddress].feeDistributor).recordVote(weight, nftId);
            IIncentiveManager(pools[poolAddress].bribeDistributor).recordVote(weight, nftId);

            pools[poolAddress].totalVotes += weight;

            voteData.poolVotes[poolAddress] += weight;
            totalVotes += weight;
        }

        voteData.isVoting = true;
        voteData.pools = _poolAddresses;
        voteData.totalVotes += (totalVotes - currentTotal);

        emit VoteCast(nftId, _poolAddresses, weights);
    }

    function distributeRewards(uint256 batchSize) external whenNotPaused onlyRole(DISTRIBUTOR_ROLE) nonReentrant {
        if (getCurrentEpoch() <= lastEpochTime) {
            revert VotingErrors.EpochNotFinished();
        }
        
        if (!epochRewardDistributed[getCurrentEpoch() - 1]) {
            IMinter(minter).mintForEpoch();
            epochRewardDistributed[getCurrentEpoch() - 1] = true;
        }
        uint256 currentTotalVotes = totalVotes;
        uint256 endIndex = processedPools + batchSize;

        if (endIndex > poolAddresses.length) {
            endIndex = poolAddresses.length;
        }

        for (uint256 i = processedPools; i < endIndex; i++) {
            address poolAddress = poolAddresses[i];
            uint256 poolTotalVotes = pools[poolAddress].totalVotes;
            if (poolTotalVotes == 0 || !isAlive[poolAddress]) {
                continue;
            }

            uint256 poolPercentage = (poolTotalVotes * 1e18) / currentTotalVotes;


            for (uint256 j = 0; j < rewardTokens.length; j++) {
                address token = rewardTokens[j];
                uint256 rewardAmount = (epochRewards[token] * poolPercentage) / 1e18;
                if (rewardAmount > 0) {
                    address rewarder = IRewardRegistry(rewardRegistryAddress).getRewarderByPool(poolAddress);
                    _addRewardsToOffchain(rewarder, IERC20(token), rewardAmount);
                    // emit RewardAllocated(poolAddress, token, rewardAmount);
                    emit RewardsDistributedDetails(getCurrentEpoch(), poolAddress, token, rewardAmount, poolTotalVotes, currentTotalVotes, poolPercentage*100);
                }
            }
        }

        processedPools = endIndex;

        // If all pools have been processed, update epoch time
        if (processedPools >= poolAddresses.length) {            
            lastEpochTime = getCurrentEpoch();
            processedPools = 0; // Reset for the next epoch
            emit RewardsDistributed(lastEpochTime);
        }
    }

    function _addRewardsToOffchain(address rewarder, IERC20 token, uint256 tokenAmount) internal {
        require(rewarder != address(0), "Invalid rewarder address");

        uint32 startTimestamp = uint32(getCurrentEpoch()) * uint32(epochDuration);
        uint32 endTimestamp = startTimestamp + uint32(epochDuration);
        uint256 rewardPerSec = tokenAmount / (endTimestamp - startTimestamp);

        bool isNative = address(token) == address(wrappedGLMR);
        if (isNative) {
            IWGLMR(wrappedGLMR).withdraw(tokenAmount);
            require(address(this).balance >= tokenAmount, "Insufficient native token balance");
            IRewarder(rewarder).addRewardInfo{value: tokenAmount}(
                token, isNative, startTimestamp, endTimestamp, rewardPerSec
            );
        } else {
            token.safeApprove(rewarder, tokenAmount);
            require(token.allowance(address(this), rewarder) >= tokenAmount, "Approval failed");
            IRewarder(rewarder).addRewardInfo(token, isNative, startTimestamp, endTimestamp, rewardPerSec);
            token.safeApprove(rewarder, 0);
        }
    }

    function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint256 _tokenId)
        external
        ownerOrEscrow(_tokenId)
        whenNotPaused
        nonReentrant
    {
        uint256 _length = _bribes.length;
        for (uint256 i = 0; i < _length; i++) {
            IIncentiveManager(_bribes[i]).getReward(msg.sender, _tokenId, _tokens[i]);
        }
    }

    function withdrawFromManagedNft(uint256 _tokenId) external whenNotPaused nonReentrant onlyDuringEpoch(_tokenId) {
        if (!veStellaToken.isApprovedOrOwner(msg.sender, _tokenId)) revert VotingErrors.NotApprovedOrOwner();

        uint256 managedTokenId = (veStellaToken.managedInfo(_tokenId)).mNFTId;

        veStellaToken.withdrawFromManagedNFT(_tokenId);

        uint256 weight = veStellaToken.balanceOfNFT(managedTokenId);

        if (weight == 0) {
            _reset(managedTokenId);
        } else {
            _poke(managedTokenId, weight);
        }
    }

    function depositIntoManagedNft(uint256 _tokenId, uint256 _managedTokenId)
        external
        whenNotPaused
        nonReentrant
        onlyDuringEpoch(_tokenId)
    {
        if (!veStellaToken.isApprovedOrOwner(msg.sender, _tokenId)) revert VotingErrors.NotApprovedOrOwner();
        if (veStellaToken.lockType(_tokenId) != IVEStella.LockType.NORMAL) revert VotingErrors.NotNormalNFT();

        _reset(_tokenId);

        veStellaToken.depositIntoManagedNFT(_tokenId, _managedTokenId);

        uint256 voterWeight = veStellaToken.balanceOfNFT(_managedTokenId);

        nftVoteData[_tokenId].epoch = getCurrentEpoch();

        _poke(_managedTokenId, voterWeight);
    }

    function _poke(uint256 _tokenId, uint256 _voterWeight) internal {
        VoteCheckpoint storage voteData = nftVoteData[_tokenId];
        // Retrieve pools and weights from the existing vote checkpoint
        address[] memory NftPoolAddresses = voteData.pools;
        uint256[] memory weights = new uint256[](NftPoolAddresses.length);

        // Calculate total weight of the existing votes

        uint256 totalWeights = 0;
        for (uint256 i = 0; i < NftPoolAddresses.length; i++) {
            weights[i] = voteData.poolVotes[NftPoolAddresses[i]];
            totalWeights += weights[i];
        }
        // Use _vote for the core voting logic, passing all necessary parameters
        _vote(_tokenId, NftPoolAddresses, weights, _voterWeight, totalWeights);
    }

    function claimFees(address[] memory _fees, address[][] memory _tokens, uint256 _tokenId)
        external
        ownerOrEscrow(_tokenId)
        whenNotPaused
        nonReentrant
    {
        uint256 _length = _fees.length;
        for (uint256 i = 0; i < _length; i++) {
            IIncentiveManager(_fees[i]).getReward(msg.sender, _tokenId, _tokens[i]);
        }
    }

    function reset(uint256 _tokenId) external whenNotPaused onlyDuringEpoch(_tokenId) ownerOrEscrow(_tokenId) nonReentrant {
        // Now call the internal function to perform the reset
        _reset(_tokenId);
    }

    function _reset(uint256 _tokenId) internal {
        VoteCheckpoint storage voteData = nftVoteData[_tokenId];
        


        // Limit local variables and avoid repeated access of storage
        address[] memory localPoolAddresses = voteData.pools;
        for (uint256 i = 0; i < localPoolAddresses.length; i++) {
            address poolAddress = localPoolAddresses[i];
            uint256 poolVotes = voteData.poolVotes[poolAddress];

            if (poolVotes > 0) {
                // Cache `feeDistributor` and `bribeDistributor` to reduce stack usage
                address feeDistributor = pools[poolAddress].feeDistributor;
                address bribeDistributor = pools[poolAddress].bribeDistributor;

                IIncentiveManager(feeDistributor)._withdraw(poolVotes, _tokenId);
                IIncentiveManager(bribeDistributor)._withdraw(poolVotes, _tokenId);

                pools[poolAddress].totalVotes -= poolVotes;
                
                voteData.poolVotes[poolAddress] = 0;
            }
        }

        totalVotes -= voteData.totalVotes;

        voteData.totalVotes = 0;
        delete voteData.pools;
        voteData.isVoting = false;
    }

    function setMAXVOTESPEREPOCH(uint256 _maxVotesPerEpoch) external onlyRole(ADMIN_ROLE) {
        if (_maxVotesPerEpoch <= 0) {
            revert VotingErrors.InvalidVotes();
        }
        MAX_VOTES_PER_EPOCH = _maxVotesPerEpoch;
        emit MaxVotesPerEpochUpdated(_maxVotesPerEpoch);
    }

    function getPoolsVotedByNFTForEpoch(uint256 _nftId) external view returns (address[] memory) {
        return nftVoteData[_nftId].pools;
    }

    function getBribeWhiteListedRewardTokenList() external view returns (address[] memory) {
        return bribeWhiteListedRewardTokenList;
    }

    function getPoolAddresses() external view returns (address[] memory) {
        return poolAddresses;
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function getPoolVotes(address poolAddress) external view returns (uint256) {
        return pools[poolAddress].totalVotes;
    }

    function getIsPoolRegistered(address poolAddress) external view returns (bool) {
        return pools[poolAddress].isRegistered;
    }

    function getVeStella() external view returns (address) {
        return address(veStellaToken);
    }

    function getCurrentEpoch() public view returns (uint256) {
        require(epochDuration > 0, "Epoch duration not set");
        return (block.timestamp / epochDuration);
    }

    function voted(uint256 _tokenId) external view returns (bool) {
        return nftVoteData[_tokenId].isVoting;
    }

    function getPoolVotesForNFT(uint256 nftId, address pool) public view returns (uint256) {
        return nftVoteData[nftId].poolVotes[pool];
    }

    function getFeeDistributorForPool(address poolAddress) external view returns (address) {
        return pools[poolAddress].feeDistributor;
    }

    function recoverERC20(address token, uint256 amount) external onlyRole(ADMIN_ROLE) {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function recoverNative(uint256 amount) external onlyRole(ADMIN_ROLE) {
        (bool success, ) = msg.sender.call{value: amount}("");
    }
    receive() external payable {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
