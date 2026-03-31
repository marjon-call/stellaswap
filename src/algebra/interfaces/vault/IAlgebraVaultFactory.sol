// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title The interface for the Algebra Vault Factory
/// @notice This contract can be used for automatic vaults creation
/// @dev Version: Algebra Integral
interface IAlgebraVaultFactory {

  /// @notice Emitted when a AlgebraFeeReceiver address changed
  /// @param newAlgebraFeeReceiver New Algebra fee receiver address
  event AlgebraFeeReceiver(address newAlgebraFeeReceiver);

  /// @notice Emitted when a AlgebraFeeManager address change proposed
  /// @param pendingAlgebraFeeManager New pending Algebra fee manager address
  event PendingAlgebraFeeManager(address pendingAlgebraFeeManager);

  /// @notice Emitted when a new Algebra fee value proposed
  /// @param proposedNewAlgebraFee The new proposed Algebra fee value
  event AlgebraFeeProposal(uint16 proposedNewAlgebraFee);

  /// @notice Emitted when a Algebra fee proposal canceled
  event CancelAlgebraFeeProposal();

  /// @notice Emitted when a AlgebraFeeManager address changed
  /// @param newAlgebraFeeManager New Algebra fee manager address
  event AlgebraFeeManager(address newAlgebraFeeManager);

  /// @notice Emitted when the Algebra fee is changed
  /// @param newAlgebraFee The new Algebra fee value
  event AlgebraFee(uint16 newAlgebraFee);

  /// @notice Emitted when a CommunityFeeReceiver address changed
  /// @param newCommunityFeeReceiver New fee receiver address
  event CommunityFeeReceiver(address newCommunityFeeReceiver);

  event VaultCreated(address pool, address vault);

  /// @notice returns address of the community fee vault for the pool
  /// @param pool the address of Algebra Integral pool
  /// @return communityFeeVault the address of community fee vault
  function getVaultForPool(address pool) external view returns (address communityFeeVault);

  /// @notice creates the community fee vault for the pool if needed
  /// @param pool the address of Algebra Integral pool
  /// @return communityFeeVault the address of community fee vault
  function createVaultForPool(
    address pool,
    address creator,
    address deployer,
    address token0,
    address token1
  ) external returns (address communityFeeVault);

  // ### algebra factory owner permissioned actions ###

  /// @notice Accepts the proposed new Algebra fee
  /// @dev Can only be called by the factory owner.
  /// The new value will also be used for previously accumulated tokens that have not yet been withdrawn
  /// @param newAlgebraFee New Algebra fee value
  function acceptAlgebraFeeChangeProposal(uint16 newAlgebraFee) external;

  /// @notice Change community fee receiver address
  /// @dev Can only be called by the factory owner
  /// @param newCommunityFeeReceiver New community fee receiver address
  function changeCommunityFeeReceiver(address newCommunityFeeReceiver) external;

  // ### algebra fee manager permissioned actions ###

  /// @notice Transfers Algebra fee manager role
  /// @param _newAlgebraFeeManager new Algebra fee manager address
  function transferAlgebraFeeManagerRole(address _newAlgebraFeeManager) external;

  /// @notice accept Algebra FeeManager role
  function acceptAlgebraFeeManagerRole() external;

  /// @notice Proposes new Algebra fee value for protocol
  /// @dev the new value will also be used for previously accumulated tokens that have not yet been withdrawn
  /// @param newAlgebraFee new Algebra fee value
  function proposeAlgebraFeeChange(uint16 newAlgebraFee) external;

  /// @notice Cancels Algebra fee change proposal
  function cancelAlgebraFeeChangeProposal() external;

  /// @notice Change Algebra community fee part receiver
  /// @param newAlgebraFeeReceiver The address of new Algebra fee receiver
  function changeAlgebraFeeReceiver(address newAlgebraFeeReceiver) external;

  function algebraFeeManager() external view returns (address algebraFeeManager);
  function COMMUNITY_FEE_WITHDRAWER_ROLE() external view returns (bytes32);
  function hasRole(bytes32 role, address account) external view returns (bool);
  function algebraFee() external view returns (uint16);
  function algebraFeeReceiver() external view returns (address);
  function communityFeeReceiver() external view returns (address);
  function ALGEBRA_FEE_DENOMINATOR() external view returns (uint16);
  function communityFee() external view returns (uint16);
  function getFeeDistributorForPool(address poolAddress) external view returns (address);
}
