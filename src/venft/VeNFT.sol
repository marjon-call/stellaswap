// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {SafeCastLibrary} from "./libraries/SafeCastLibrary.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVeNFT} from "../interfaces/IVeNFT.sol";
import {BalanceLibrary} from "./libraries/BalanceLibrary.sol";
import {IIncentiveManagerFactory} from "../interfaces/IIncentiveManagerFactory.sol";
import {IIncentiveManager} from "../interfaces/IIncentiveManager.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IVoting} from "../interfaces/IVoting.sol";
import {veNFTErrors} from "../libraries/veNFTErrors.sol";

interface NFTART {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface IVeNFTGovernance {
    function setMaxDelegates(uint256 _maxDelegates) external;
    function addTokenToOwnerList(address owner, uint256 tokenId) external;
    function removeTokenFromOwnerList(address owner, uint256 tokenId) external;
    function tokenOfOwnerByIndex(address owner, uint256 tokenIndex) external view returns (uint256);
    function delegates(address delegator) external view returns (address);
    function getVotes(address account) external view returns (uint256);
    function getPastVotes(address account, uint256 timestamp) external view returns (uint256);
    function getPastTotalSupply(uint256 timestamp) external view returns (uint256);
    function moveTokenDelegates(address srcRep, address dstRep, uint256 tokenId) external;
    function delegateInternal(address delegator, address delegatee) external;
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s,
        string memory name
    ) external returns (address);
    function undelegate(address user, address caller) external;
}

contract VeNFT is IVeNFT, ERC721, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCastLibrary for uint256;
    using SafeCastLibrary for int128;

    address public immutable stella;
    address public voter;
    address public configDistributorFactory;
    address public governance;
    address public nftArtContract;

    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME
    }

    struct ManagedNFT {
        address lockedReward;
        address freeReward;
    }

    struct ManagedInfo {
        uint256 mNFTId;
        uint256 weight;
    }

    uint256 internal constant WEEK = 1 weeks;
    uint256 internal constant MAXTIME = 2 * 365 * 86400;
    int128 internal constant iMAXTIME = 2 * 365 * 86400;
    uint256 internal constant MULTIPLIER = 1 ether;
    uint256 public constant MAX_BPS = 10000;
    bytes32 public constant CONFIGURATION_ROLE = keccak256("CONFIGURATION_ROLE");
    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant CREATE_MANAGED_NFT_ROLE = keccak256("CREATE_MANAGED_NFT_ROLE");

    uint256 public earlyWithdrawPercentage = 5000;
    uint256 public epoch;
    uint256 public supply;
    uint256 public permanentLockedBalance;
    uint256 public tokenId;

    bool internal emergencyWithdrawEnabled = false;

    mapping(uint256 => LockedBalance) internal _locked;
    mapping(uint256 => UserPoint[1000000000]) internal _userPointHistory;
    mapping(uint256 => uint256) public userPointEpoch;
    mapping(uint256 => int128) public slopeChanges;
    mapping(uint256 => EpochPoint) internal _epochPointHistory;
    mapping(uint256 => LockType) public lockType;
    mapping(uint256 => ManagedNFT) public managedNFTRewards;
    mapping(uint256 => ManagedInfo) public managedInfo;
    mapping(uint256 => uint256) public ownershipChange;

    mapping(bytes32 => mapping(address => bool)) private _roles;

    modifier onlyRole(bytes32 role) {
        if (!hasRole(role, msg.sender)) revert veNFTErrors.CallerDoesNotHaveRequiredRole();
        _;
    }

    mapping(address => bool) public canSplit;

    event Deposit(
        address indexed provider,
        uint256 indexed tokenId,
        DepositType indexed depositType,
        uint256 value,
        uint256 locktime,
        uint256 ts
    );
    event Supply(uint256 prevSupply, uint256 supply);
    event Withdraw(address indexed provider, uint256 indexed tokenId, uint256 value, uint256 ts);
    event Split(
        uint256 indexed _from,
        uint256 indexed _tokenId0,
        uint256 indexed _tokenId1,
        address _sender,
        uint256 _splitAmount0,
        uint256 _splitAmount1,
        uint256 _locktime,
        uint256 _timestamp
    );

    event Merge(
        address indexed _sender,
        uint256 indexed _tokenId0,
        uint256 indexed _tokenId1,
        uint256 _amountToken0,
        uint256 _amountToken1,
        uint256 _amountFinal,
        uint256 _locktime,
        uint256 _timestamp
    );

    event CreateManagedNFT(
        address indexed _recipient,
        uint256 indexed _mTokenId,
        address indexed _from,
        address _lockedManagedReward,
        address _freeManagedReward
    );

    event DepositManaged(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed managedTokenId,
        uint256 amount,
        uint256 timestamp
    );

    event WithdrawManaged(
        address indexed _owner, uint256 indexed _tokenId, uint256 indexed _mTokenId, uint256 _weight, uint256 _timestamp
    );

    event VoterUpdated(address oldVoter, address newVoter);
    event DelegateChanged(address delegator, address currentDelegate, address delegatee);

    constructor(address _stella, address _configDistributorFactory) ERC721("StellaSwap veSTELLA", "veSTELLA-NFT") {
        stella = _stella;
        configDistributorFactory = _configDistributorFactory;
        _epochPointHistory[0].blk = block.number;

        _epochPointHistory[0].ts = block.timestamp;

        _grantRole(SUPER_ADMIN_ROLE, msg.sender, true);
        _grantRole(CONFIGURATION_ROLE, msg.sender, true);
        _grantRole(CREATE_MANAGED_NFT_ROLE, msg.sender, true);

        emit Transfer(address(0), address(this), tokenId);
    }

    function setConfigDistributorFactory(address _configDistributorFactory) external onlyRole(CONFIGURATION_ROLE) {
        configDistributorFactory = _configDistributorFactory;
    }

    function tokenURI(uint256 _tokenId) public virtual override(ERC721) view returns (string memory) {
        return NFTART(nftArtContract).tokenURI(_tokenId);
    }

    function setGovernance(address _governance) external onlyRole(CONFIGURATION_ROLE) {
        governance = _governance;
    }

    function setNFTArtContract(address _nftArtContract) external onlyRole(CONFIGURATION_ROLE) {
        nftArtContract = _nftArtContract;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function grantRole(bytes32 role, address account) external onlyRole(SUPER_ADMIN_ROLE) {
        _grantRole(role, account, true);
    }

    function toggleRole(bytes32 role, address account, bool _toggle) external onlyRole(SUPER_ADMIN_ROLE) {
        _grantRole(role, account, _toggle);
    }

    function _grantRole(bytes32 role, address account, bool _toggle) internal {
        _roles[role][account] = _toggle;
    }

    function setEarlyWithdrawPercentage(uint256 _percentage) external onlyRole(CONFIGURATION_ROLE) {
        if (_percentage > MAX_BPS) revert veNFTErrors.PercentageExceedsMax();
        earlyWithdrawPercentage = _percentage;
    }

    function toggleEmergencyWithdraw(bool _enabled) external onlyRole(CONFIGURATION_ROLE) {
        emergencyWithdrawEnabled = _enabled;
    }

    function locked(uint256 _tokenId) external view returns (LockedBalance memory) {
        return _locked[_tokenId];
    }

    function userPointHistory(uint256 _tokenId, uint256 _loc) external view returns (UserPoint memory) {
        return _userPointHistory[_tokenId][_loc];
    }

    function pointHistory(uint256 _loc) external view returns (EpochPoint memory) {
        return _epochPointHistory[_loc];
    }

    function _checkpoint(uint256 _tokenId, LockedBalance memory _oldLocked, LockedBalance memory _newLocked) internal {
        UserPoint memory uOld;
        UserPoint memory uNew;
        int128 oldDslope = 0;
        int128 newDslope = 0;
        uint256 _epoch = epoch;

        if (_tokenId != 0) {
            uNew.permanent = _newLocked.isPermanent ? _newLocked.amount.toUint256() : 0;
            if (_oldLocked.end > block.timestamp && _oldLocked.amount > 0) {
                uOld.slope = _oldLocked.amount / iMAXTIME;
                uOld.bias = uOld.slope * (_oldLocked.end - block.timestamp).toInt128();
            }
            if (_newLocked.end > block.timestamp && _newLocked.amount > 0) {
                uNew.slope = _newLocked.amount / iMAXTIME;
                uNew.bias = uNew.slope * (_newLocked.end - block.timestamp).toInt128();
            }
            oldDslope = slopeChanges[_oldLocked.end];
            if (_newLocked.end != 0) {
                if (_newLocked.end == _oldLocked.end) {
                    newDslope = oldDslope;
                } else {
                    newDslope = slopeChanges[_newLocked.end];
                }
            }
        }

        EpochPoint memory lastPoint =
            EpochPoint({bias: 0, slope: 0, ts: block.timestamp, blk: block.number, permanentLockBalance: 0});
        if (_epoch > 0) {
            lastPoint = _epochPointHistory[_epoch];
        }
        uint256 lastCheckpoint = lastPoint.ts;
        EpochPoint memory initialLastPoint = EpochPoint({
            bias: lastPoint.bias,
            slope: lastPoint.slope,
            ts: lastPoint.ts,
            blk: lastPoint.blk,
            permanentLockBalance: lastPoint.permanentLockBalance
        });
        uint256 blockSlope = 0;
        if (block.timestamp > lastPoint.ts) {
            blockSlope = (MULTIPLIER * (block.number - lastPoint.blk)) / (block.timestamp - lastPoint.ts);
        }

        {
            uint256 t_i = (lastCheckpoint / WEEK) * WEEK;
            for (uint256 i = 0; i < 255; ++i) {
                t_i += WEEK;
                int128 d_slope = 0;
                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    d_slope = slopeChanges[t_i];
                }
                lastPoint.bias -= lastPoint.slope * (t_i - lastCheckpoint).toInt128();
                lastPoint.slope += d_slope;
                if (lastPoint.bias < 0) {
                    lastPoint.bias = 0;
                }
                if (lastPoint.slope < 0) {
                    lastPoint.slope = 0;
                }
                lastCheckpoint = t_i;
                lastPoint.ts = t_i;
                lastPoint.blk = initialLastPoint.blk + (blockSlope * (t_i - initialLastPoint.ts)) / MULTIPLIER;
                _epoch += 1;
                if (t_i == block.timestamp) {
                    lastPoint.blk = block.number;
                    break;
                } else {
                    _epochPointHistory[_epoch] = lastPoint;
                }
            }
        }

        if (_tokenId != 0) {
            lastPoint.slope += (uNew.slope - uOld.slope);
            lastPoint.bias += (uNew.bias - uOld.bias);
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            lastPoint.permanentLockBalance = permanentLockedBalance;
        }


        if (_epoch != 1 && _epochPointHistory[_epoch - 1].ts == block.timestamp) {
            _epochPointHistory[_epoch - 1] = lastPoint;
        } else {
            epoch = _epoch;
            _epochPointHistory[_epoch] = lastPoint;
        }

        if (_tokenId != 0) {
            if (_oldLocked.end > block.timestamp) {
                oldDslope += uOld.slope;
                if (_newLocked.end == _oldLocked.end) {
                    oldDslope -= uNew.slope;
                }
                slopeChanges[_oldLocked.end] = oldDslope;
            }

            if (_newLocked.end > block.timestamp) {
                if ((_newLocked.end > _oldLocked.end)) {
                    newDslope -= uNew.slope;
                    slopeChanges[_newLocked.end] = newDslope;
                }
            }


            uNew.ts = block.timestamp;
            uNew.blk = block.number;
            uint256 userEpoch = userPointEpoch[_tokenId];
            if (userEpoch != 0 && _userPointHistory[_tokenId][userEpoch].ts == block.timestamp) {
                _userPointHistory[_tokenId][userEpoch] = uNew;
            } else {
                userPointEpoch[_tokenId] = ++userEpoch;
                _userPointHistory[_tokenId][userEpoch] = uNew;
            }
        }
    }

    function checkpoint() external nonReentrant {
        _checkpoint(0, LockedBalance(0, 0, false), LockedBalance(0, 0, false));
    }

    function _depositFor(
        uint256 _tokenId,
        uint256 _value,
        uint256 _unlockTime,
        LockedBalance memory _oldLocked,
        DepositType _depositType
    ) internal {
        LockedBalance memory newLocked;

        uint256 supplyBefore = supply;
        supply = supplyBefore + _value;

        (newLocked.amount, newLocked.end, newLocked.isPermanent) =
            (_oldLocked.amount, _oldLocked.end, _oldLocked.isPermanent);

        // Adding to existing lock, or if a lock is expired - creating a new one
        newLocked.amount += _value.toInt128();

        if (_unlockTime != 0) {
            newLocked.end = _unlockTime;
        }
        _locked[_tokenId] = newLocked;


        _checkpoint(_tokenId, _oldLocked, newLocked);

        address from = _msgSender();
        if (_value != 0) {
            IERC20(stella).safeTransferFrom(from, address(this), _value);
        }
        emit Deposit(from, _tokenId, _depositType, _value, newLocked.end, block.timestamp);
        emit Supply(supplyBefore, supplyBefore + _value);
    }

    function _createLock(uint256 _value, uint256 _lockDurationInSeconds, address _mintTo) internal returns (uint256) {
        uint256 _unlockTime = ((block.timestamp + _lockDurationInSeconds) / WEEK) * WEEK; // Locktime is rounded down to weeks
        if (_value == 0) revert veNFTErrors.ValueCannotBeZero();
        if (_unlockTime <= block.timestamp) revert veNFTErrors.LockExpired();
        if (_unlockTime > block.timestamp + MAXTIME + WEEK) revert veNFTErrors.LockDurationTooLong();
        uint256 _tokenId = ++tokenId;
        _mint(_mintTo, _tokenId);

        _depositFor(_tokenId, _value, _unlockTime, _locked[_tokenId], DepositType.CREATE_LOCK_TYPE);
        return _tokenId;
    }

    function createLock(uint256 _value, uint256 _lockDurationInSeconds) external nonReentrant returns (uint256) {
        return _createLock(_value, _lockDurationInSeconds, _msgSender());
    }

    function createLockFor(uint256 _value, uint256 _unlockTime, address _mintTo)
        external
        nonReentrant
        returns (uint256)
    {
        return _createLock(_value, _unlockTime, _mintTo);
    }

    function _increaseAmountFor(uint256 _tokenId, uint256 _value, DepositType _depositType) internal {
        LockType _lockType = lockType[_tokenId];
        if (_lockType == LockType.MANAGED) revert veNFTErrors.NotNormalNFT();
        LockedBalance memory oldLocked = _locked[_tokenId];

        if (_value == 0) revert veNFTErrors.ValueCannotBeZero();
        if (oldLocked.amount <= 0) revert veNFTErrors.LockExpired();
        if (oldLocked.end <= block.timestamp && !oldLocked.isPermanent) revert veNFTErrors.LockExpired();
        if (oldLocked.isPermanent) permanentLockedBalance += _value;
        _depositFor(_tokenId, _value, 0, oldLocked, _depositType);

        if (_lockType == LockType.MNFT) {
            address lockedReward = managedNFTRewards[_tokenId].lockedReward;
            IERC20(stella).safeApprove(lockedReward, _value);
            IIncentiveManager(lockedReward).notifyRewardAmount(stella, _value);
            IERC20(stella).safeApprove(lockedReward, 0);
        }
    }

    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    function increaseAmount(uint256 _tokenId, uint256 _value) external nonReentrant {
        if (!_isApprovedOrOwner(_msgSender(), _tokenId)) revert veNFTErrors.NotApprovedOrOwner();
        _increaseAmountFor(_tokenId, _value, DepositType.INCREASE_LOCK_AMOUNT);
    }

    function depositFor(uint256 _tokenId, uint256 _value) external nonReentrant {
        _increaseAmountFor(_tokenId, _value, DepositType.DEPOSIT_FOR_TYPE);
    }

    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external nonReentrant {
        if (!_isApprovedOrOwner(_msgSender(), _tokenId)) revert veNFTErrors.NotApprovedOrOwner();
        if (lockType[_tokenId] != LockType.NORMAL) revert veNFTErrors.NotNormalNFT();

        LockedBalance memory oldLocked = _locked[_tokenId];
        if (oldLocked.isPermanent) revert veNFTErrors.LockExpiredOrPermanent();
        uint256 unlockTime = ((block.timestamp + _lockDuration) / WEEK) * WEEK; // Locktime is rounded down to weeks

        if (oldLocked.end <= block.timestamp) revert veNFTErrors.LockExpired();
        if (oldLocked.amount <= 0) revert veNFTErrors.ValueCannotBeZero();
        if (unlockTime <= oldLocked.end) revert veNFTErrors.CanOnlyIncreaseLockDuration();
        if (unlockTime > block.timestamp + MAXTIME) revert veNFTErrors.LockDurationTooLong();

        _depositFor(_tokenId, 0, unlockTime, oldLocked, DepositType.INCREASE_UNLOCK_TIME);
    }

    function withdraw(uint256 _tokenId) external nonReentrant {
        address sender = _msgSender();
        if (!_isApprovedOrOwner(sender, _tokenId)) revert veNFTErrors.NotApprovedOrOwner();
        if (lockType[_tokenId] != LockType.NORMAL) revert veNFTErrors.NotNormalNFT();
        if (IVoting(voter).voted(_tokenId)) revert veNFTErrors.AlreadyVotedForNFT();

        LockedBalance memory oldLocked = _locked[_tokenId];
        if (oldLocked.isPermanent) revert veNFTErrors.LockExpiredOrPermanent();

        uint256 value = oldLocked.amount.toUint256();
        _burn(_tokenId);
        _locked[_tokenId] = LockedBalance(0, 0, false);

        uint256 supplyBefore = supply;
        supply = supplyBefore - value;

        _checkpoint(_tokenId, oldLocked, LockedBalance(0, 0, false));

        if (block.timestamp >= oldLocked.end) {
            IERC20(stella).safeTransfer(sender, value);
        } else {
            uint256 penaltyAmount = (value * earlyWithdrawPercentage) / MAX_BPS;
            uint256 withdrawAmount = value - penaltyAmount;
            IERC20(stella).safeTransfer(sender, withdrawAmount);
            IERC20(stella).safeTransfer(address(0x000000000000000000000000000000000000dEaD), penaltyAmount);
        }

        emit Withdraw(sender, _tokenId, value, block.timestamp);
        emit Supply(supplyBefore, supplyBefore - value);
    }

    function emergencyWithdraw(uint256 _tokenId) external nonReentrant {
        if (!emergencyWithdrawEnabled) revert veNFTErrors.EmergencyWithdrawDisabled();

        address sender = _msgSender();
        if (!_isApprovedOrOwner(sender, _tokenId)) revert veNFTErrors.NotApprovedOrOwner();
        if (lockType[_tokenId] != LockType.NORMAL) revert veNFTErrors.NotNormalNFT();

        LockedBalance memory oldLocked = _locked[_tokenId];
        if (oldLocked.isPermanent) revert veNFTErrors.LockExpiredOrPermanent();

        uint256 value = oldLocked.amount.toUint256();

        _burn(_tokenId);
        _locked[_tokenId] = LockedBalance(0, 0, false);

        uint256 supplyBefore = supply;
        supply = supplyBefore - value;

        _checkpoint(_tokenId, oldLocked, LockedBalance(0, 0, false));

        IERC20(stella).safeTransfer(sender, value);

        emit Withdraw(sender, _tokenId, value, block.timestamp);
        emit Supply(supplyBefore, supplyBefore - value);
    }

    function _balanceOfNFTAt(uint256 _tokenId, uint256 _timestamp) internal view returns (uint256) {
        return BalanceLibrary.balanceOfNFTAt(userPointEpoch, _userPointHistory, _tokenId, _timestamp);
    }

    function _supplyAt(uint256 _timestamp) internal view returns (uint256) {
        return BalanceLibrary.supplyAt(slopeChanges, _epochPointHistory, epoch, _timestamp);
    }

    function balanceOfNFTAt(uint256 _tokenId, uint256 _timestamp) external view returns (uint256) {
        return _balanceOfNFTAt(_tokenId, _timestamp);
    }

    function balanceOfNFT(uint256 _tokenId) public view returns (uint256) {
        if (ownershipChange[_tokenId] == block.number) return 0;
        return _balanceOfNFTAt(_tokenId, block.timestamp);
    }

    function totalSupply() external view returns (uint256) {
        return _supplyAt(block.timestamp);
    }

    function totalSupplyAt(uint256 _timestamp) external view returns (uint256) {
        return _supplyAt(_timestamp);
    }

    function split(uint256 _from, uint256 _amount)
        external
        nonReentrant
        returns (uint256 _tokenId0, uint256 _tokenId1)
    {
        address sender = _msgSender();
        address owner = _ownerOf(_from);

        if (owner == address(0)) revert veNFTErrors.NoOwner();
        if (IVoting(voter).voted(_from)) revert veNFTErrors.AlreadyVotedForNFT();
        if (!canSplit[owner] && !canSplit[address(0)]) revert veNFTErrors.SplitNotAllowed();
        if (!_isApprovedOrOwner(sender, _from)) revert veNFTErrors.NotApprovedOrOwner();
        if (lockType[_from] != LockType.NORMAL) revert veNFTErrors.NotNormalNFT();

        LockedBalance memory newLocked = _locked[_from];
        if (newLocked.end <= block.timestamp && !newLocked.isPermanent) revert veNFTErrors.LockExpiredOrPermanent();

        int128 _splitAmount = _amount.toInt128();
        if (_splitAmount <= 0) revert veNFTErrors.SplitAmountCannotBeZero();
        if (newLocked.amount <= _splitAmount) revert veNFTErrors.SplitAmountTooLarge();

        _burn(_from);
        _locked[_from] = LockedBalance(0, 0, false);
        _checkpoint(_from, newLocked, LockedBalance(0, 0, false));

        newLocked.amount -= _splitAmount;
        _tokenId0 = _createSplitNFT(owner, newLocked);

        newLocked.amount = _splitAmount;
        _tokenId1 = _createSplitNFT(owner, newLocked);

        emit Split(
            _from,
            _tokenId0,
            _tokenId1,
            sender,
            _locked[_tokenId0].amount.toUint256(),
            _splitAmount.toUint256(),
            newLocked.end,
            block.timestamp
        );
    }

    function _createSplitNFT(address _to, LockedBalance memory _newLocked) private returns (uint256 _tokenId) {
        _tokenId = ++tokenId;
        _locked[_tokenId] = _newLocked;
        _checkpoint(_tokenId, LockedBalance(0, 0, false), _newLocked);
        _mint(_to, _tokenId);
    }

    function toggleSplit(address _account, bool _bool) external onlyRole(CONFIGURATION_ROLE) {
        canSplit[_account] = _bool;
    }

    function merge(uint256 _tokenId0, uint256 _tokenId1) external nonReentrant {
        address sender = _msgSender();
        if (_tokenId0 == _tokenId1) revert veNFTErrors.CannotMergeSameNFT();
        if (!_isApprovedOrOwner(sender, _tokenId0)) revert veNFTErrors.NotApprovedOrOwner();
        if (!_isApprovedOrOwner(sender, _tokenId1)) revert veNFTErrors.NotApprovedOrOwner();
        if (IVoting(voter).voted(_tokenId0)) revert veNFTErrors.AlreadyVotedForNFT();
        if (IVoting(voter).voted(_tokenId1)) revert veNFTErrors.AlreadyVotedForNFT();
        if (lockType[_tokenId0] != LockType.NORMAL) revert veNFTErrors.NotNormalNFT();
        if (lockType[_tokenId1] != LockType.NORMAL) revert veNFTErrors.NotNormalNFT();

        LockedBalance memory sourceLock = _locked[_tokenId0];
        LockedBalance memory targetLock = _locked[_tokenId1];
        if (sourceLock.isPermanent) revert veNFTErrors.LockExpiredOrPermanent();
        if (targetLock.end <= block.timestamp && !targetLock.isPermanent) revert veNFTErrors.LockExpiredOrPermanent();

        // Calculate new end time as the maximum of both locks
        uint256 newEndTime = targetLock.end >= sourceLock.end ? targetLock.end : sourceLock.end;

        // Burn source NFT and clear its lock
        _burn(_tokenId0);
        _locked[_tokenId0] = LockedBalance(0, 0, false);
        _checkpoint(_tokenId0, sourceLock, LockedBalance(0, 0, false));

        // Create merged lock
        LockedBalance memory mergedLock;
        mergedLock.amount = targetLock.amount + sourceLock.amount;
        mergedLock.isPermanent = targetLock.isPermanent;

        if (mergedLock.isPermanent) {
            permanentLockedBalance += sourceLock.amount.toUint256();
        } else {
            mergedLock.end = newEndTime;
        }

        // Update target NFT with merged lock
        _checkpoint(_tokenId1, targetLock, mergedLock);
        _locked[_tokenId1] = mergedLock;

        emit Merge(
            sender,
            _tokenId0,
            _tokenId1,
            sourceLock.amount.toUint256(),
            targetLock.amount.toUint256(),
            mergedLock.amount.toUint256(),
            mergedLock.end,
            block.timestamp
        );
    }

 
    function createManagedNFT(address _recipient)
        external
        nonReentrant
        onlyRole(CREATE_MANAGED_NFT_ROLE)
        returns (uint256 _tokenId)
    {
        _tokenId = ++tokenId;
        _mint(_recipient, _tokenId);

        // Create permanent lock with 0 initial amount
        _depositFor(
            _tokenId,
            0, // value
            0, // unlockTime
            LockedBalance(0, 0, true), // permanent lock
            DepositType.CREATE_LOCK_TYPE
        );

        lockType[_tokenId] = LockType.MNFT;
        address freeReward = IIncentiveManagerFactory(configDistributorFactory).createIncentiveManager(
            voter, address(this), IIncentiveManagerFactory.RewardType.FREE_REWARDS, msg.sender
        );
        address lockedReward = IIncentiveManagerFactory(configDistributorFactory).createIncentiveManager(
            voter, address(this), IIncentiveManagerFactory.RewardType.LOCKED_REWARDS, msg.sender
        );
        managedNFTRewards[_tokenId] = ManagedNFT(lockedReward, freeReward);
        emit CreateManagedNFT(_recipient, _tokenId, address(this), lockedReward, freeReward);
    }

    function depositIntoManagedNFT(uint256 _tokenId, uint256 _managedTokenId) external nonReentrant {
        if (msg.sender != voter) revert veNFTErrors.NotVoter();
        if (lockType[_managedTokenId] != LockType.MNFT) revert veNFTErrors.NotManagedNFT();
        if (lockType[_tokenId] != LockType.NORMAL) revert veNFTErrors.NotNormalNFT();
        if (_balanceOfNFTAt(_tokenId, block.timestamp) <= 0) revert veNFTErrors.ValueCannotBeZero();

        int128 currentAmount = _locked[_tokenId].amount;

        if (_locked[_tokenId].isPermanent) {
            permanentLockedBalance -= currentAmount.toUint256();

        }

        LockedBalance memory emptyLock = LockedBalance(0, 0, false);
        _checkpoint(_tokenId, _locked[_tokenId], emptyLock);
        _locked[_tokenId] = emptyLock;

        uint256 depositAmount = currentAmount.toUint256();
        permanentLockedBalance += depositAmount;

        LockedBalance memory managedLock = _locked[_managedTokenId];
        managedLock.amount += currentAmount;


        _checkpoint(_managedTokenId, _locked[_managedTokenId], managedLock);
        _locked[_managedTokenId] = managedLock;

        managedInfo[_tokenId] = ManagedInfo(_managedTokenId, depositAmount);

        lockType[_tokenId] = LockType.MANAGED;

        address lockedReward = managedNFTRewards[_managedTokenId].lockedReward;
        IIncentiveManager(lockedReward).recordVote(depositAmount, _tokenId);
        address freeReward = managedNFTRewards[_managedTokenId].freeReward;
        IIncentiveManager(freeReward).recordVote(depositAmount, _tokenId);

        emit DepositManaged(_ownerOf(_tokenId), _tokenId, _managedTokenId, depositAmount, block.timestamp);
    }


    function withdrawFromManagedNFT(uint256 _tokenId) external nonReentrant {
        uint256 managedTokenId = managedInfo[_tokenId].mNFTId;
        if (msg.sender != voter) revert veNFTErrors.NotVoter();
        if (managedTokenId == 0) revert veNFTErrors.NoOwner();
        if (lockType[_tokenId] != LockType.MANAGED) revert veNFTErrors.NotNormalNFT();

        address lockedReward = managedNFTRewards[managedTokenId].lockedReward;
        address freeReward = managedNFTRewards[managedTokenId].freeReward;

        uint256 depositAmount = managedInfo[_tokenId].weight;
        uint256 earnedRewards = IIncentiveManager(lockedReward).calculateReward(address(stella), _tokenId);
        uint256 totalAmount = depositAmount + earnedRewards;

        uint256 unlockTime = ((block.timestamp + MAXTIME) / WEEK) * WEEK;

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(stella);
        IIncentiveManager(lockedReward).getReward(address(this), _tokenId, rewardTokens);

        LockedBalance memory newUserLock = LockedBalance(totalAmount.toInt128(), unlockTime, false);
        _checkpoint(_tokenId, _locked[_tokenId], newUserLock);
        _locked[_tokenId] = newUserLock;

        LockedBalance memory managedLock = _locked[managedTokenId];
        managedLock.amount -=
            (totalAmount.toInt128() < managedLock.amount ? totalAmount.toInt128() : managedLock.amount);

        permanentLockedBalance -= (totalAmount < permanentLockedBalance ? totalAmount : permanentLockedBalance);


        _checkpoint(managedTokenId, _locked[managedTokenId], managedLock);
        _locked[managedTokenId] = managedLock;

        IIncentiveManager(lockedReward)._withdraw(depositAmount, _tokenId);
        IIncentiveManager(freeReward)._withdraw(depositAmount, _tokenId);

        delete managedInfo[_tokenId];
        delete lockType[_tokenId];

        emit WithdrawManaged(_ownerOf(_tokenId), _tokenId, managedTokenId, totalAmount, block.timestamp);
    }

    function setVoter(address _voter) external onlyRole(CONFIGURATION_ROLE) {
        if (_voter == address(0)) revert veNFTErrors.ZeroAddress();
        address oldVoter = voter;
        voter = _voter;
        emit VoterUpdated(oldVoter, _voter);
    }

    // ==== GOVERNANCE DELEGATION ====

    function setMaxDelegates(uint256 _maxDelegates) external onlyRole(CONFIGURATION_ROLE) {
        if (governance == address(0)) return;
        IVeNFTGovernance(governance).setMaxDelegates(_maxDelegates);
    }

    function tokenOfOwnerByIndex(address _owner, uint256 _tokenIndex) public view returns (uint256) {
        if (governance == address(0)) revert("Governance not set");
        return IVeNFTGovernance(governance).tokenOfOwnerByIndex(_owner, _tokenIndex);
    }

    function _afterTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        virtual
        override
    {
        if (governance != address(0)) {
            if (from == address(0)) {
                // mint
                IVeNFTGovernance(governance).addTokenToOwnerList(to, firstTokenId);
                IVeNFTGovernance(governance).moveTokenDelegates(
                    address(0), IVeNFTGovernance(governance).delegates(to), firstTokenId
                );
            }

            if (to == address(0)) {
                // burn
                IVeNFTGovernance(governance).removeTokenFromOwnerList(from, firstTokenId);
                IVeNFTGovernance(governance).moveTokenDelegates(
                    IVeNFTGovernance(governance).delegates(from), address(0), firstTokenId
                );
            }

            if (from != address(0) && to != address(0)) {
                // transfer
                IVeNFTGovernance(governance).removeTokenFromOwnerList(from, firstTokenId);
                IVeNFTGovernance(governance).addTokenToOwnerList(to, firstTokenId);
                IVeNFTGovernance(governance).moveTokenDelegates(
                    IVeNFTGovernance(governance).delegates(from),
                    IVeNFTGovernance(governance).delegates(to),
                    firstTokenId
                );
            }
        }
        ownershipChange[firstTokenId] = block.number;

    }


    function delegates(address delegator) public view returns (address) {
        if (governance == address(0)) return delegator;
        return IVeNFTGovernance(governance).delegates(delegator);
    }


    function getVotes(address account) external view returns (uint256) {
        if (governance == address(0)) return 0;
        return IVeNFTGovernance(governance).getVotes(account);
    }

    function getPastVotes(address account, uint256 timestamp) public view returns (uint256) {
        if (governance == address(0)) return 0;
        return IVeNFTGovernance(governance).getPastVotes(account, timestamp);
    }

    function getPastTotalSupply(uint256 timestamp) external view returns (uint256) {
        if (governance == address(0)) return _supplyAt(timestamp);
        return IVeNFTGovernance(governance).getPastTotalSupply(timestamp);
    }

    function delegate(address delegatee) public nonReentrant {
        if (governance == address(0)) return;
        if (delegatee == address(0)) delegatee = msg.sender;
        return IVeNFTGovernance(governance).delegateInternal(msg.sender, delegatee);
    }

    function undelegate(address user) external nonReentrant {
        if (governance == address(0)) return;
        IVeNFTGovernance(governance).undelegate(user, msg.sender);
    }

    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        nonReentrant
    {
        if (governance == address(0)) return;
        IVeNFTGovernance(governance).delegateBySig(delegatee, nonce, expiry, v, r, s, name());
    }
}
