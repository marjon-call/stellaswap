// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.20;
pragma abicoder v1;

import './interfaces/vault/IAlgebraVaultFactory.sol';
import './interfaces/IAlgebraFactory.sol';
import './interfaces/vault/IVoter.sol';
import './AlgebraCommunityVault.sol';
/// @title Algebra vault factory stub
/// @notice This contract is used to set AlgebraCommunityVault as communityVault in new pools
contract AlgebraVaultFactoryStub is IAlgebraVaultFactory {

  bytes32 public constant COMMUNITY_FEE_WITHDRAWER_ROLE = keccak256('COMMUNITY_FEE_WITHDRAWER');
  bytes32 public constant COMMUNITY_FEE_VAULT_ADMINISTRATOR = keccak256('COMMUNITY_FEE_VAULT_ADMINISTRATOR');
  bytes32 public constant SUPER_ADMIN_ROLE = keccak256('SUPER_ADMIN_ROLE');


  address private immutable factory;
  address public voter;
  /// @notice the address of AlgebraCommunityVault
  // address public immutable defaultAlgebraCommunityVault;

  /// @notice Address to which community fees are sent from vault
  address public communityFeeReceiver;
  
/// @notice The percentage of the protocol fee that Algebra will receive
  /// @dev Value in thousandths,i.e. 1e-3
  uint16 public communityFee;

  /// @notice The percentage of the protocol fee that Algebra will receive
  /// @dev Value in thousandths,i.e. 1e-3
  uint16 public algebraFee;
  /// @notice Represents whether there is a new Algebra fee proposal or not
  bool public hasNewAlgebraFeeProposal;
  /// @notice Suggested Algebra fee value
  uint16 public proposedNewAlgebraFee;
  /// @notice Address of recipient Algebra part of community fee
  address public algebraFeeReceiver;
  /// @notice Address of Algebra fee manager
  address public algebraFeeManager;
  address private _pendingAlgebraFeeManager;

  uint16 public constant ALGEBRA_FEE_DENOMINATOR = 1000;

  mapping(bytes32 => mapping(address => bool)) private _roles;
  mapping(address => address) public poolVaults; // poolAddress => communityFeeVault

  modifier onlyAlgebraFeeManager() {
    require(msg.sender == algebraFeeManager, 'only algebra fee manager');
    _;
  }

  modifier onlyRole(bytes32 role) {
      require(hasRole(role, msg.sender), 'caller does not have required role');
      _;
  }

  modifier onlyFactoryOrAdmin() {
      require(msg.sender == factory || hasRole(COMMUNITY_FEE_VAULT_ADMINISTRATOR, msg.sender), 'caller is not factory or admin');
      _;
  }
  

  constructor(address _factory, address _algebraFeeManager) {
    (factory, algebraFeeManager) = (_factory, _algebraFeeManager);
    // algebraFee = _algebraFees;
    // communityFee = _communityFees;
    // algebraFeeReceiver = _algebraFeeManager;
    _grantRole(SUPER_ADMIN_ROLE, msg.sender);
    _grantRole(COMMUNITY_FEE_VAULT_ADMINISTRATOR, msg.sender);
    _grantRole(COMMUNITY_FEE_WITHDRAWER_ROLE, msg.sender);
  }

  // ==== ACCESS CONTROL =====
  function hasRole(bytes32 role, address account) public view returns (bool) {
      return _roles[role][account];
  }

  function grantRole(bytes32 role, address account) external onlyRole(SUPER_ADMIN_ROLE) {
      _grantRole(role, account);
  }

  function revokeRole(bytes32 role, address account) external onlyRole(SUPER_ADMIN_ROLE) {
      _roles[role][account] = false;
  }

  function _grantRole(bytes32 role, address account) internal {
      _roles[role][account] = true;
  }

  // ==== POOL OPERATIONS =====

  /// @inheritdoc IAlgebraVaultFactory
  function getVaultForPool(address _pool) external view override returns (address) {
    return poolVaults[_pool];
  }

  /// @inheritdoc IAlgebraVaultFactory
  function createVaultForPool(address _pool, address _creator, address _deployer, address _token0, address _token1) external override onlyFactoryOrAdmin returns (address) {
    AlgebraCommunityVault vault = new AlgebraCommunityVault(address(this), _pool);
    poolVaults[_pool] = address(vault);
    emit VaultCreated(_pool, address(vault));
    return address(vault);
  }

  // ==== ALGEBRA OPERATIONS =====

  /// @inheritdoc IAlgebraVaultFactory
  function acceptAlgebraFeeChangeProposal(uint16 newAlgebraFee) external override onlyRole(COMMUNITY_FEE_VAULT_ADMINISTRATOR) {
    require(hasNewAlgebraFeeProposal, 'not proposed');
    require(newAlgebraFee == proposedNewAlgebraFee, 'invalid new fee');

    // note that the new value will be used for previously accumulated tokens that have not yet been withdrawn
    algebraFee = newAlgebraFee;
    (proposedNewAlgebraFee, hasNewAlgebraFeeProposal) = (0, false);
    emit AlgebraFee(newAlgebraFee);
  }
  
  /// @inheritdoc IAlgebraVaultFactory
  function transferAlgebraFeeManagerRole(address _newAlgebraFeeManager) external override onlyAlgebraFeeManager {
    _pendingAlgebraFeeManager = _newAlgebraFeeManager;
    emit PendingAlgebraFeeManager(_newAlgebraFeeManager);
  }

  /// @inheritdoc IAlgebraVaultFactory
  function acceptAlgebraFeeManagerRole() external override {
    require(msg.sender == _pendingAlgebraFeeManager);
    (_pendingAlgebraFeeManager, algebraFeeManager) = (address(0), msg.sender);
    emit AlgebraFeeManager(msg.sender);
  }

  /// @inheritdoc IAlgebraVaultFactory
  function proposeAlgebraFeeChange(uint16 newAlgebraFee) external override onlyAlgebraFeeManager {
    require(newAlgebraFee <= ALGEBRA_FEE_DENOMINATOR);
    require(newAlgebraFee != proposedNewAlgebraFee && newAlgebraFee != algebraFee);
    (proposedNewAlgebraFee, hasNewAlgebraFeeProposal) = (newAlgebraFee, true);
    emit AlgebraFeeProposal(newAlgebraFee);
  }

  /// @inheritdoc IAlgebraVaultFactory
  function cancelAlgebraFeeChangeProposal() external override onlyAlgebraFeeManager {
    (proposedNewAlgebraFee, hasNewAlgebraFeeProposal) = (0, false);
    emit CancelAlgebraFeeProposal();
  }

  /// @inheritdoc IAlgebraVaultFactory
  function changeAlgebraFeeReceiver(address newAlgebraFeeReceiver) external override onlyAlgebraFeeManager {
    require(newAlgebraFeeReceiver != address(0));
    require(newAlgebraFeeReceiver != algebraFeeReceiver);
    algebraFeeReceiver = newAlgebraFeeReceiver;
    emit AlgebraFeeReceiver(newAlgebraFeeReceiver);
  }

  // ==== COMMUNITY OPERATIONS =====
  /// @inheritdoc IAlgebraVaultFactory
  function changeCommunityFeeReceiver(address newCommunityFeeReceiver) external override onlyRole(COMMUNITY_FEE_VAULT_ADMINISTRATOR) {
    require(newCommunityFeeReceiver != address(0));
    require(newCommunityFeeReceiver != communityFeeReceiver);
    communityFeeReceiver = newCommunityFeeReceiver;
    emit CommunityFeeReceiver(newCommunityFeeReceiver);
  }

  function setVoter(address _voter) external onlyRole(COMMUNITY_FEE_VAULT_ADMINISTRATOR) {
    require(_voter != address(0), 'invalid voter address');
    voter = _voter;
  }

  function setCommunityFee(uint16 _communityFee) external onlyRole(COMMUNITY_FEE_VAULT_ADMINISTRATOR) {
    require(_communityFee != 0, 'invalid community fee');
    communityFee = _communityFee;
  }

  function getFeeDistributorForPool(address poolAddress) external view returns (address) {
    if(voter == address(0)) return address(0);
    return IVoter(voter).getFeeDistributorForPool(poolAddress);
  }
}
