// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// ============ Minimal Interfaces ============

interface IVeNFT {
    struct LockedBalance {
        int128 amount;
        uint256 end;
        bool isPermanent;
    }

    struct ManagedInfo {
        uint256 mNFTId;
        uint256 weight;
    }

    enum LockType { NORMAL, MANAGED, MNFT }

    function stella() external view returns (address);
    function voter() external view returns (address);
    function tokenId() external view returns (uint256);
    function supply() external view returns (uint256);
    function epoch() external view returns (uint256);
    function permanentLockedBalance() external view returns (uint256);
    function earlyWithdrawPercentage() external view returns (uint256);
    function locked(uint256 _tokenId) external view returns (LockedBalance memory);
    function lockType(uint256 _tokenId) external view returns (LockType);
    function managedInfo(uint256 _tokenId) external view returns (ManagedInfo memory);
    function balanceOfNFT(uint256 _tokenId) external view returns (uint256);
    function balanceOfNFTAt(uint256 _tokenId, uint256 _timestamp) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalSupplyAt(uint256 _timestamp) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function governance() external view returns (address);
    function configDistributorFactory() external view returns (address);
    function nftArtContract() external view returns (address);
    function canSplit(address) external view returns (bool);

    function createLock(uint256 _value, uint256 _lockDurationInSeconds) external returns (uint256);
    function createLockFor(uint256 _value, uint256 _unlockTime, address _mintTo) external returns (uint256);
    function increaseAmount(uint256 _tokenId, uint256 _value) external;
    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external;
    function withdraw(uint256 _tokenId) external;
    function depositFor(uint256 _tokenId, uint256 _value) external;
    function merge(uint256 _tokenId0, uint256 _tokenId1) external;
    function split(uint256 _from, uint256 _amount) external returns (uint256, uint256);
    function checkpoint() external;

    function depositIntoManagedNFT(uint256 _tokenId, uint256 _managedTokenId) external;
    function withdrawFromManagedNFT(uint256 _tokenId) external;
}

interface IAlgebraVaultFactory {
    function factory() external view returns (address);
    function voter() external view returns (address);
    function algebraFee() external view returns (uint16);
    function communityFee() external view returns (uint16);
    function algebraFeeReceiver() external view returns (address);
    function algebraFeeManager() external view returns (address);
    function communityFeeReceiver() external view returns (address);
    function ALGEBRA_FEE_DENOMINATOR() external view returns (uint16);
    function hasNewAlgebraFeeProposal() external view returns (bool);
    function proposedNewAlgebraFee() external view returns (uint16);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function poolVaults(address pool) external view returns (address);
    function getVaultForPool(address _pool) external view returns (address);
    function getFeeDistributorForPool(address poolAddress) external view returns (address);

    function createVaultForPool(address _pool, address _creator, address _deployer, address _token0, address _token1) external returns (address);
    function setVoter(address _voter) external;
    function setCommunityFee(uint16 _communityFee) external;
}

interface IFundsManager {
    function ST_GLMR() external view returns (address);
    function WITHDRAWAL() external view returns (address);
    function AUTH_MANAGER() external view returns (address);
    function LEDGER_BEACON() external view returns (address);
    function glmrAUM() external view returns (uint256);
    function bufferedDeposits() external view returns (uint256);
    function bufferedRedeems() external view returns (uint256);
    function depositCap() external view returns (uint256);
    function treasuryFees() external view returns (uint16);
    function FEE_DIVISOR() external view returns (uint16);
    function lastSyncedRound() external view returns (uint32);
    function multiLedgerUnbondingEnabled() external view returns (bool);
    function UNBOND_DELAY_ROUNDS() external view returns (uint8);
    function ledgerStake(address) external view returns (uint256);
    function ledgerBorrow(address) external view returns (uint256);
    function getLedgerAddresses() external view returns (address[] memory);
    function getUnbonded(address _holder) external view returns (uint256 waiting, uint256 unbonded);
    function getTreasury() external view returns (address);
}

interface IVoter {
    function veStellaToken() external view returns (address);
    function wrappedGLMR() external view returns (address);
    function minter() external view returns (address);
    function rewardRegistryAddress() external view returns (address);
    function incentiveManagerFactory() external view returns (address);
    function totalVotes() external view returns (uint256);
    function poolCount() external view returns (uint256);
    function epochDuration() external view returns (uint256);
    function lastEpochTime() external view returns (uint256);
    function MAX_VOTES_PER_EPOCH() external view returns (uint256);
    function COOL_DOWN_PERIOD() external view returns (uint256);
    function startOfVoteEpoch() external view returns (uint256);
    function emergencyPaused() external view returns (bool);
    function isAlive(address) external view returns (bool);
    function isRewardToken(address) external view returns (bool);
    function voted(uint256 _tokenId) external view returns (bool);
    function poolAddresses(uint256 index) external view returns (address);
    function getPoolAddresses() external view returns (address[] memory);
    function getRewardTokens() external view returns (address[] memory);
    function getPoolVotes(address poolAddress) external view returns (uint256);
    function getIsPoolRegistered(address poolAddress) external view returns (bool);
    function getVeStella() external view returns (address);
    function getCurrentEpoch() external view returns (uint256);
    function getFeeDistributorForPool(address poolAddress) external view returns (address);
    function getPoolsVotedByNFTForEpoch(uint256 _nftId) external view returns (address[] memory);
    function getBribeWhiteListedRewardTokenList() external view returns (address[] memory);

    function vote(uint256 nftId, address[] memory _poolAddresses, uint256[] memory weights) external;
    function reset(uint256 _tokenId) external;
    function claimFees(address[] memory _fees, address[][] memory _tokens, uint256 _tokenId) external;
    function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint256 _tokenId) external;
    function distributeRewards(uint256 batchSize) external;
}

interface IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// ============ Test Contract ============

contract PoCTest is Test {
    // ---- PROXY ADDRESSES (use these for PoC) ----
    // stGLMR Funds Manager (proxy -> impl 0xab7a2d483294344350767abde2f47be621d28f2a)
    address constant FUNDS_MANAGER = 0x3069A7955408D261069F7D4ed3eFdB9Ea8D95d7b;
    // Voter (proxy -> impl 0x09641ad3f0d01dd9e293d6431a6b543bebf9550f)
    address constant VOTER = 0x091a177FbC5f493920c2e027eDc89658c1cED495;

    // ---- DIRECT ADDRESSES (not behind proxy) ----
    // veNFT
    address constant VENFT = 0xfa62B5962a7923A2910F945268AA65C943D131e9;
    // Algebra Vault Factory (Integral Vault Factory)
    address constant ALGEBRA_VAULT_FACTORY = 0x9B81835b2f7B51447D5E4C07Ae18f05dfe627150;

    // ---- COMMON TOKENS ----
    // WGLMR (Wrapped GLMR on Moonbeam)
    address constant WGLMR = 0xAcc15dC74880C9944775448304B263D191c6077F;
    // STELLA token
    address constant STELLA = 0x0E358838ce72d5e61E0018a2ffaC4bEC5F4c88d2;

    // ---- TYPED REFERENCES ----
    IVeNFT venft = IVeNFT(VENFT);
    IAlgebraVaultFactory algebraVaultFactory = IAlgebraVaultFactory(ALGEBRA_VAULT_FACTORY);
    IFundsManager fundsManager = IFundsManager(FUNDS_MANAGER);
    IVoter voter = IVoter(VOTER);
    IERC20 stella = IERC20(STELLA);
    IERC20 wglmr = IERC20(WGLMR);

    uint256 constant FORK_BLOCK = 15034800;

    function setUp() public {
        vm.createSelectFork(vm.envString("MOONBEAM_RPC_URL"), FORK_BLOCK);
    }

    function test_PoC() public {
        // Write your exploit here
    }

}
