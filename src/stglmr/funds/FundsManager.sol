// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/Roles.sol";
import "../interfaces/ILedger.sol";
import "../interfaces/ISTGLMR.sol";
import "../interfaces/IWithdrawal.sol";
import "../interfaces/IAuthManager.sol";
import "../interfaces/IFundsManager.sol";
import "../interfaces/ILedgerFactory.sol";

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "../ledger/Ledger.sol";
import "../utils/TransferHelper.sol";

/**
 * @dev Core of the stGLMR protocol designed to handle accounting and 
 * staking flows accross all ledgers
 *
 * - Holds pooled GLMR and orchestrates bonding/unbonding across multiple ledgers.
 * - Maintains per-ledger target allocations and realized balances.
 * - Drives the daily rebalance loop, distributing deposits and servicing redemptions.
 */
contract FundsManager is IFundsManager, Initializable {
    using SafeMath for uint256;
    using SafeCast for uint256;

    /// @notice stGLMR token address 
    address public ST_GLMR;

    /// @notice Withdrawal address that manages user redeem batches.
    address public WITHDRAWAL;
 
    /// @notice AuthManager address providing role-based access control.
    address public AUTH_MANAGER;
 
    /// @notice Ledger beacon for upgradeable ledgers.
    address public LEDGER_BEACON;
        
    /// @notice Factory that deploys new ledger proxies.
    address private LEDGER_FACTORY;

    /// @notice Last staking “round” we processed in {rebalanceLedgerStakes};
    uint32 public lastSyncedRound;

    /// @dev Default fee is 10% of rewards (1000 / 10000 bps).
    uint16 internal DEFAULT_TREASURY_FEE;

    /// @notice Fee divisor (basis points denominator).
    uint16 public FEE_DIVISOR;

    /// @notice Current treasury fee in basis points.
    uint16 public treasuryFees;

    /// @notice Address receiving protocol fee in minted stGLMR shares.
    address private treasury;

    /// @notice Deposits waiting to be allocated to ledgers or netted against redemptions.
    uint256 public bufferedDeposits;

    /// @notice Redemptions waiting to be serviced from ledgers or netted against deposits.
    uint256 public bufferedRedeems;

    /// @inheritdoc IFundsManager
    uint256 public override glmrAUM;

    /// @notice Max aggregate deposits the system will accept.
    uint256 public depositCap;

    /// @notice When true, more than one unbond request can be opened on single ledger.
    bool public multiLedgerUnbondingEnabled;

    /// @notice Number of rounds to wait before unbonded funds can be withdrawn
    /// @dev This value is network-specific (devnet, testnet, mainnet)
    uint8 public UNBOND_DELAY_ROUNDS;

    /// @dev Active ledgers that receive deposits and may be selected for unbond.
    address[] private enabledLedgers;

    /// @dev Ledgers put into “draining” mode; do not receive new deposits.
    address[] private disabledLedgers;

    /// @dev Paused flag per ledger.
    mapping(address => bool) private pausedledgers;

    /// @dev Registry of known ledger proxies - enabled or disabled.
    mapping(address => bool) private ledgerByAddress;

    /**
     * @notice Desired (virtual) stake per ledger decided by FM.
     * @dev Sum over enabled+disabled can be ≤/>= AUM during transitions.
     */
    mapping(address => uint256) public ledgerStake;
 
    /**
     * @notice Actual GLMR that FM has sent to a ledger (principal on ledger).
     * @dev Increases via {transferToLedger}, decreases via {transferFromLedger}.
     */
    mapping(address => uint256) public ledgerBorrow;

     /// @notice Emitted when the ledger beacon address is set.
    event LedgerBeaconUpdated(address addr);

    /// @notice Emitted when the ledger factory address is set.
    event LedgerFactoryUpdated(address addr);

    /// @notice Emitted when a new ledger is added (enabled).
    event LedgerAdded(address addr);

    /// @notice Emitted when a ledger is moved from enabled → disabled.
    event LedgerDisabled(address addr);

    /// @notice Emitted when a ledger is moved from disabled → enabled.
    event LedgerEnabled(address addr);

    /// @notice Emitted when a disabled+paused ledger has its pause removed.
    event LedgerPaused(address addr);

    /// @notice Emitted when a paused ledger is resumed (pause flag cleared).
    event LedgerResumed(address addr);

    /// @notice Emitted when a disabled, empty ledger is fully removed from the registry.
    event LedgerRemoved(address addr);

    /// @notice Emitted when rewards are recognized and applied to AUM and a ledger.
    event Rewards(address ledger, uint256 rewards, uint256 balance);

    /// @notice Emitted when a user claim is executed in the Withdrawal contract.
    event Claimed(address indexed receiver, uint256 amount);

    /// @notice Emitted when protocol fee is updated (bps).
    event FeeSet(uint16 fee);

    /// @notice Emitted when max unlocking chunks is pushed to all ledgers.
    event MaxUnlockingChunksUpdated(uint256 maxChunks);

    /// @notice Emitted when deposit cap is changed.
    event DepositCapUpdated(uint256 oldCap, uint256 newCap, address indexed caller);

    /// @notice Emitted when treasury address is updated.
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury, address indexed caller);

    /// @notice Emitted when multi-ledger unbonding toggle changes.
    event MultiLedgerUnbondingToggled(bool enabled, address indexed caller);

    modifier onlyStGlmr() {
        require(
            ST_GLMR == msg.sender,
            "Only stGLMR can call this"
        );
        _;
    }

    modifier auth(bytes32 role) {
        require(IAuthManager(AUTH_MANAGER).has(role, msg.sender), "FM: UNAUTHOROZED");
        _;
    }

    function initialize(
        address _authManager,
        address _withdrawal,
        address _treasury,
        uint256 _depositCap,
        uint8 _unbondDelayRounds
    ) external initializer {
        require(_authManager != address(0), "FM: INCORRECT_AUTHMANAGER_ADDRESS");

        AUTH_MANAGER = _authManager;
        FEE_DIVISOR = 10000;
        DEFAULT_TREASURY_FEE = 1000;

        depositCap = _depositCap;
        treasury = _treasury;
        treasuryFees = DEFAULT_TREASURY_FEE;
        UNBOND_DELAY_ROUNDS = _unbondDelayRounds;

        
        WITHDRAWAL = _withdrawal;
        IWithdrawal(WITHDRAWAL).setFundsManager(address(this));
    }

    /**
     * @notice Permanently set stGLMR token address.
     * @param _stglmr stGLMR token address.
     */
    function setSTGLMR(address _stglmr) external auth(Roles.ROLE_SPEC_MANAGER) {
        require(ST_GLMR == address(0), "FM: ST_GLMR_ALREADY_SET");
        require(_stglmr != address(0), "FM: INCORRECT_ST_GLMR_ADDRESS");
        ST_GLMR = _stglmr;
    }

    /**
     * @notice Update the global deposit cap.
     * @param _depositCap New cap in wei (must be > 0).
     */
    function setDepositCap(uint256 _depositCap) external auth(Roles.ROLE_SPEC_MANAGER) {
        require(_depositCap > 0, "FM: INCORRECT_NEW_CAP");
        uint256 oldCap = depositCap;
        depositCap = _depositCap;
        emit DepositCapUpdated(oldCap, _depositCap, msg.sender);
    }

    /**
     * @notice Update treasury address.
     * @param _treasury New treasury address.
     */
    function setTreasury(address _treasury) external auth(Roles.ROLE_TREASURY) {
        require(_treasury != address(0), "FM: INCORRECT_TREASURY_ADDRESS");
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury, msg.sender);
    }

    /**
     * @notice Get the current treasury address.
     * @return Current treasury address.
     */
    function getTreasury() external view returns (address) {
        return treasury;
    }

    /**
     * @notice Set protocol fee in basis points.
     * @dev Must be less than 50% (5000 bps).
     * @param _fee New fee in bps.
     */
    function setFee(uint16 _fee) external auth(Roles.ROLE_FEE_MANAGER) {
        require(_fee < 5000, "FM: FEE TO HIGH");
        treasuryFees = _fee;
        emit FeeSet(_fee);
    }

    /**
     * @notice Propagate a new “max unlocking chunks” value to all ledgers.
     * @dev Governance knob to constrain number of concurrent unbonds per ledger.
     * @param _maxChunks Value in [1..50].
     */
    function setMaxUnlockingChunks(uint256 _maxChunks) external auth(Roles.ROLE_SPEC_MANAGER) {
        address[] memory allLedgers = getLedgerAddresses();
        for (uint256 i = 0; i < allLedgers.length; i++) {
            ILedger(allLedgers[i]).setMaxUnlockingChunks(_maxChunks);
        }
        
        emit MaxUnlockingChunksUpdated(_maxChunks);
    }

    /**
     * @notice Enable/disable multi-ledger unbonding per rebalance.
     * @dev When disabled, at most one ledger target is reduced per rebalance (legacy mode).
     * @param _enabled True to allow unbonding from multiple ledgers.
     */
    function toggleMultiLedgerUnbonding(bool _enabled) external auth(Roles.ROLE_SPEC_MANAGER) {
        multiLedgerUnbondingEnabled = _enabled;
        emit MultiLedgerUnbondingToggled(_enabled, msg.sender);
    }

    /**
     * @notice Set ledger beacon address (beacon proxy infra).
     * @param _ledgerBeacon Beacon address (non-zero, can only be set once).
     */
    function setLedgerBeacon(address _ledgerBeacon) external auth(Roles.ROLE_BEACON_MANAGER) {
        require(LEDGER_BEACON == address(0), "FM: LEDGER_BEACON_ALREADY_SET");
        require(_ledgerBeacon != address(0), "FM: INCORRECT_BEACON_ADDRESS");
        LEDGER_BEACON = _ledgerBeacon;
        emit LedgerBeaconUpdated(_ledgerBeacon);
    }

    /**
     * @notice Set ledger factory address (beacon proxy infra).
     * @param _ledgerFactory Factory address (non-zero).
     */
    function setLedgerFactory(address _ledgerFactory) external auth(Roles.ROLE_BEACON_MANAGER) {
        require(_ledgerFactory != address(0), "FM: INCORRECT_FACTORY_ADDRESS");
        LEDGER_FACTORY = _ledgerFactory;
        emit LedgerFactoryUpdated(_ledgerFactory);
    }

     /**
     * @notice Record an incoming deposit from stGLMR.
     * @dev Increases AUM and buffers the deposit for next rebalance.
     *      Enforces {depositCap}.
     */
    function deposit() payable public onlyStGlmr() {
        require(glmrAUM + msg.value <= depositCap, "FM: DEPOSITS_EXCEED_CAP");
        uint256 _amount = msg.value;
        glmrAUM += _amount;
        bufferedDeposits += _amount;
    }

    /**
     * @notice Record a redemption from stGLMR and enqueue it in Withdrawal.
     * @dev Decreases AUM and buffers redeem demand until serviced by unbonds or netting.
     * @param _user End user redeeming.
     * @param _amount Redemption amount in wei.
     */
    function redeem(address _user, uint256 _amount) public onlyStGlmr() {
        glmrAUM -= _amount;
        bufferedRedeems += _amount;

        IWithdrawal(WITHDRAWAL).redeem(_user, _amount);

    }

    /**
     * @notice Forward a user claim to the Withdrawal contract (stGLMR-initiated).
     * @param _user Claiming user.
     */
    function claim(address _user) external onlyStGlmr() {
        uint256 amount = IWithdrawal(WITHDRAWAL).claim(_user);
        emit Claimed(_user, amount);
    }

    /**
     * @notice Add a new ledger (enabled) for a given collator candidate.
     * @dev Deploys a new beacon proxy via {LEDGER_FACTORY}; registers it and assigns candidate.
     * @param _candidate Collator candidate the ledger will delegate to.
     * @return ledger Address of the newly created ledger.
     */
    function addLedger(address _candidate) external auth(Roles.ROLE_LEDGER_MANAGER) returns(address) {
        require(LEDGER_BEACON != address(0), "FM: UNSPECIFIED_LEDGER_BEACON");
        require(LEDGER_FACTORY != address(0), "FM: UNSPECIFIED_LEDGER_FACTORY");

        address ledger = ILedgerFactory(LEDGER_FACTORY).createLedger();
        ILedger(ledger).setCandidate(_candidate);
        enabledLedgers.push(ledger);
        ledgerByAddress[ledger] = true;

        emit LedgerAdded(ledger);
        return ledger;

    }

    /**
    * @notice Disable ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev That method put ledger to "draining" mode, after ledger drained it can be removed
    * @param _ledgerAddress - target ledger address
    */
    function disableLedger(address _ledgerAddress) external auth(Roles.ROLE_LEDGER_MANAGER) {
        _disableLedger(_ledgerAddress);
    }

    /**
     * @notice Re-enable a previously disabled ledger.
     * @dev Reverts if not registered, not disabled, or explicitly paused.
     * @param _ledgerAddress Target ledger to re-enable.
     */
    function enableLedger(address _ledgerAddress) external auth(Roles.ROLE_LEDGER_MANAGER) {
        _enableLedger(_ledgerAddress);
    }

    /**
    * @notice Disable ledger and pause all redeems for that ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev That method pause all stake changes for ledger
    * @param _ledgerAddress - target ledger address
    */
    function emergencyPauseLedger(address _ledgerAddress) external auth(Roles.ROLE_LEDGER_MANAGER) {
        _disableLedger(_ledgerAddress);
        pausedledgers[_ledgerAddress] = true;
        emit LedgerPaused(_ledgerAddress);
    }

    /**
    * @notice Allow redeems from paused ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @param _ledgerAddress - target ledger address
    */
    function resumeLedger(address _ledgerAddress) external auth(Roles.ROLE_LEDGER_MANAGER) {
        require(pausedledgers[_ledgerAddress], "FM: LEDGER_NOT_PAUSED");
        delete pausedledgers[_ledgerAddress];
        emit LedgerResumed(_ledgerAddress);
    }

    /**
    * @notice Remove ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev That method cannot be executed for running ledger, so need to drain funds
    * @param _ledgerAddress - target ledger address
    */
    function removeLedger(address _ledgerAddress) external auth(Roles.ROLE_LEDGER_MANAGER) {
        require(ledgerByAddress[_ledgerAddress], "FM: LEDGER_NOT_FOUND");
        require(ledgerStake[_ledgerAddress] == 0, "FM: LEDGER_HAS_NON_ZERO_STAKE");
        
        uint256 ledgerIdx = _findLedger(_ledgerAddress, false);
        require(ledgerIdx != type(uint256).max, "FM: LEDGER_NOT_DISABLED");
        
        ILedger ledger = ILedger(_ledgerAddress);
        require(ledger.isEmpty(), "FM: LEDGER_IS_NOT_EMPTY");

        address lastLedger = disabledLedgers[disabledLedgers.length - 1];
        disabledLedgers[ledgerIdx] = lastLedger;
        disabledLedgers.pop();

        delete ledgerByAddress[_ledgerAddress];

        if (pausedledgers[_ledgerAddress]) {
            delete pausedledgers[_ledgerAddress];
        }

        emit LedgerRemoved(_ledgerAddress);
    }

     /**
     * @notice Send principal to a ledger (ledger pull).
     * @dev Only a registered ledger may call. Enforces that target is not exceeded.
     * @param _amount Amount to transfer in wei.
     */
    function transferToLedger(uint256 _amount) external {
        require(ledgerByAddress[msg.sender], "FUNDS_MANAGER: NOT_FROM_LEDGER");
        uint256 _bondedAmount = ILedger(msg.sender).getActiveAmount();
        require(_bondedAmount + _amount <= ledgerStake[msg.sender], "FUNDS_MANAGER: LEDGER_NOT_ENOUGH_STAKE");

        ledgerBorrow[msg.sender] += _amount;
        TransferHelper.safeTransferETH(msg.sender, _amount);
    }

    /**
     * @notice Receive funds back from a ledger (principal + extra).
     * @dev Only a registered ledger may call. Extra is recognized as rewards and added to AUM.
     * @param _amount Principal component being returned.
     * @param _extra Extra (rewards/dust) component being returned.
     */
    function transferFromLedger(uint256 _amount, uint256 _extra) external override {
        require(ledgerByAddress[msg.sender], "FUNDS_MANAGER: NOT_FROM_LEDGER");
        if (_extra > 0) { // if we get extra, distribute as rewards.
            glmrAUM += _extra;
            bufferedDeposits += _extra;
        }
        ledgerBorrow[msg.sender] -= _amount;
        TransferHelper.safeTransferETH(WITHDRAWAL, _amount);
    }

    function resetLedgerStake() external override {
        require(ledgerByAddress[msg.sender], "FUNDS_MANAGER: NOT_FROM_LEDGER");

        ledgerStake[msg.sender] = 0;
    }

     /**
     * @notice Core rebalance routine.
     * @dev
     * - Tick Withdrawal era.
     * - Normalize accounting drift between `ledgerStake` and `ledgerBorrow`.
     * - First try to satisfy redemptions from disabled ledgers (draining).
     * - Net deposits and redemptions; forward net to Withdrawal if possible.
     * - If net > 0 → distribute bonds equally across enabled ledgers.
     * - If net < 0 → open unbonds on one or multiple enabled ledgers (configurable).
     */
    function rebalanceLedgerStakes() external auth(Roles.ROLE_REBALANCE_MANAGER) {
        uint32 currentRound = IParachainStaking(0x0000000000000000000000000000000000000800).round();

        if (currentRound > lastSyncedRound) {
            _rebalanceLedgerStakes();

            lastSyncedRound = currentRound;
        }
    }

    /**
     * @notice Recognize rewards surfaced by a ledger and update AUM and ledger balances.
     * @dev Called by ledgers when they detect “extra” above known principal inflows.
     *      Mints fee shares to treasury according to `treasuryFees`.
     * @param _totalRewards Rewards amount in wei.
     * @param _ledgerBalance Ledger’s (telemetry) balance at the time of accounting.
     */
    function distributeRewards(uint256 _totalRewards, uint256 _ledgerBalance) external {
        require(ledgerByAddress[msg.sender], "FUNDS_MANAGER: NOT_FROM_LEDGER");
        glmrAUM += _totalRewards;

        ledgerStake[msg.sender] += _totalRewards;
        ledgerBorrow[msg.sender] += _totalRewards;

        uint256 _rewards = _totalRewards * treasuryFees / uint256(FEE_DIVISOR);
        uint256 denom = glmrAUM  - _rewards;
        uint256 shares2Mint = glmrAUM;

        if (denom > 0) shares2Mint = _rewards * _getStGLMRSupply() / denom;
        ISTGLMR(ST_GLMR).mintSharesForReward(treasury, shares2Mint);

        emit Rewards(msg.sender, _totalRewards, _ledgerBalance);
    }

     /**
     * @notice Return all ledger addresses enabled then disabled.
     */
    function getLedgerAddresses() public view returns (address[] memory) {
        address[] memory _ledgers = new address[](enabledLedgers.length + disabledLedgers.length);

        for (uint i = 0; i < enabledLedgers.length  + disabledLedgers.length; i++) {
            _ledgers[i] = i < enabledLedgers.length ?
                enabledLedgers[i] : disabledLedgers[i - enabledLedgers.length];
        }

        return _ledgers;
    }

    /**
    * @notice Return unbonded tokens amount for user
    * @param _holder - user account for whom need to calculate unbonding
    * @return waiting - amount of tokens which are not unbonded yet
    * @return unbonded - amount of token which unbonded and ready to claim
    */
    function getUnbonded(address _holder) external view returns (uint256 waiting, uint256 unbonded) {
        return IWithdrawal(WITHDRAWAL).getRedeemStatus(_holder);
    }

    function _rebalanceLedgerStakes() internal {
        IWithdrawal(WITHDRAWAL).newEra();

        uint256 totalStakeExcess;
        uint256 length = enabledLedgers.length + disabledLedgers.length;

        for (uint256 i = 0; i < length; ++i) {
            address ledgerAddr = i < enabledLedgers.length ? 
                enabledLedgers[i] : disabledLedgers[i - enabledLedgers.length];

            uint256 allocated = ledgerStake[ledgerAddr];
            uint256 actualManaged = ledgerBorrow[ledgerAddr];
            uint256 available = address(this).balance - bufferedDeposits;

            if (allocated > actualManaged) {
                uint256 ledgerStakeExcess = allocated - actualManaged;
                if (totalStakeExcess + ledgerStakeExcess <= available) { // @dev should revert here
                    totalStakeExcess += ledgerStakeExcess;

                    // correcting the ledger's active stake record
                    ledgerStake[ledgerAddr] -= ledgerStakeExcess;
                }
            }
        }

        if (totalStakeExcess > 0) bufferedDeposits += totalStakeExcess;

        // first try to distribute redeems accross disabled ledgers
        if (disabledLedgers.length > 0 && bufferedRedeems > 0) {
            bufferedRedeems = _processDisabledLedgers(bufferedRedeems);
        }

        if (bufferedDeposits > 0 && bufferedRedeems > 0) {
            uint256 maxImmediateTransfer = bufferedDeposits > bufferedRedeems ? bufferedRedeems : bufferedDeposits;                

            if (maxImmediateTransfer > 0) {
                bufferedDeposits -= maxImmediateTransfer;
                bufferedRedeems -= maxImmediateTransfer;
                TransferHelper.safeTransferETH(WITHDRAWAL, maxImmediateTransfer);
            }
        }

        int256 stake = bufferedDeposits.toInt256() - bufferedRedeems.toInt256();

        // Allocation on enabled ledgers
        //   stake > 0 : distrubte bonds equally to all ledgers
        //   stake < 0 : one-ledger-per-day round-robin unbonding 
        if (stake > 0) {
            _updateBondForLedger(uint256(stake));

            bufferedDeposits = 0;  
        } else if (stake < 0)  {
            uint256 consumed = _updateUnbondForLedger(uint256(-stake));

            if (consumed > 0) {
                bufferedRedeems -= consumed;
            }

            bufferedDeposits = 0;     
        }
    }

    function _updateBondForLedger(uint256 _amount) internal {
        uint256 _length = enabledLedgers.length;
        if (_length == 0) revert();

        uint256 _totalChange;
        uint256 _amountToAdd = _amount / _length;

        for (uint256 i = 0; i < _length; ++i) {
            if (_amountToAdd > 0) {
                ledgerStake[enabledLedgers[i]] += _amountToAdd;
                _totalChange += _amountToAdd;
            }
        }

        uint256 _remaining = _amount - _totalChange;

        if (_remaining > 0) {
            ledgerStake[enabledLedgers[0]] += _remaining;
        }
    }

    function _updateUnbondForLedger(uint256 _amount) internal returns (uint256 _consumed) {
        if (_amount == 0) return 0;

        uint256 length = enabledLedgers.length;

        if (length == 0) return 0;

        uint256 remaining = _amount;

        for (uint256 k = 0; k < length && remaining > 0; ++k) {
            address _ledgerAddr = enabledLedgers[k];
            uint256 _allocated = ledgerStake[_ledgerAddr];
            
            if (ILedger(_ledgerAddr).canSafelyUnbond() && _allocated > 0) {
                uint256 toConsume = remaining < _allocated ? remaining : _allocated;
                ledgerStake[_ledgerAddr] = _allocated - toConsume;
                _consumed += toConsume;
                remaining -= toConsume;
                
                // If multi-ledger unbonding is disabled, stop after first ledger
                if (!multiLedgerUnbondingEnabled) {
                    break; // exactly one ledger per rebalance (legacy mode)
                }
            }
        }
    }

    function _processDisabledLedgers(uint256 redeems) internal returns(uint256 remaining) {
        uint256 disabledLength = disabledLedgers.length;

        uint256 stakesSum;
        remaining = redeems;

        for (uint256 i = 0; i < disabledLength; ++i) {
            address ledgerAddr = disabledLedgers[i];
            // Only include ledgers that are not paused AND can safely unbond
            if (!pausedledgers[ledgerAddr] && ILedger(ledgerAddr).canSafelyUnbond()) {
                stakesSum += ledgerStake[ledgerAddr];
            }
        }

        if (stakesSum == 0) return redeems;

        for (uint256 i = 0; i < disabledLength && remaining > 0; ++i) {
            address ledgerAddr = disabledLedgers[i];
            // Only process ledgers that are not paused AND can safely unbond
            if (!pausedledgers[ledgerAddr] && ILedger(ledgerAddr).canSafelyUnbond()) {
                uint256 currentStake = ledgerStake[ledgerAddr];
                uint256 decrement = currentStake <= remaining ? currentStake : remaining;
                ledgerStake[ledgerAddr] = currentStake - decrement;
                remaining -= decrement;
            }
        }
    }

    function _disableLedger(address _ledgerAddress) internal {
        require(ledgerByAddress[_ledgerAddress], "FM: LEDGER_NOT_FOUND");
        uint256 ledgerIdx = _findLedger(_ledgerAddress, true);
        require(ledgerIdx != type(uint256).max, "FM: LEDGER_NOT_ENABLED");

        address lastLedger = enabledLedgers[enabledLedgers.length - 1];
        enabledLedgers[ledgerIdx] = lastLedger;
        enabledLedgers.pop();

        disabledLedgers.push(_ledgerAddress);

        emit LedgerDisabled(_ledgerAddress);
    }

    function _enableLedger(address _ledgerAddress) internal {
        require(ledgerByAddress[_ledgerAddress], "FM: LEDGER_NOT_FOUND");

        // Must currently be in the disabled list
        uint256 idx = _findLedger(_ledgerAddress, false);
        require(idx != type(uint256).max, "FM: LEDGER_NOT_DISABLED");

        // Safety guard: don’t re-enable if explicitly paused
        require(!pausedledgers[_ledgerAddress], "FM: LEDGER_PAUSED");

        // Remove from disabledLedgers via swap-pop
        address last = disabledLedgers[disabledLedgers.length - 1];
        disabledLedgers[idx] = last;
        disabledLedgers.pop();

        // Push into enabledLedgers
        enabledLedgers.push(_ledgerAddress);

        emit LedgerEnabled(_ledgerAddress);
    }

    /**
    * @notice Returns enabled or disabled ledger index by given address
    * @return enabled or disabled ledger index or uint256_max if not found
    */
    function _findLedger(address _ledgerAddress, bool _enabled) internal view returns(uint256) {
        uint256 length = _enabled ? enabledLedgers.length : disabledLedgers.length;
        for (uint256 i = 0; i < length; ++i) {
            address ledgerAddress = _enabled ? enabledLedgers[i] : disabledLedgers[i];
            if (ledgerAddress == _ledgerAddress) {
                return i;
            }
        }
        return type(uint256).max;
    }

    /**
     * @return the total amount of shares of STGLMR.
     */
    function _getStGLMRSupply() internal view returns (uint256) {
        return IERC20Upgradeable(ST_GLMR).totalSupply();
    } 

    /// @notice payable function needed to receive GLMR
    receive() external payable {}
}
