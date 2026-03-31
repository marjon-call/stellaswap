// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.20;

import './libraries/SafeTransfer.sol';
import './libraries/FullMath.sol';

import './interfaces/vault/IAlgebraCommunityVault.sol';
import './interfaces/vault/IIncentiveManager.sol';
import './interfaces/vault/IAlgebraVaultFactory.sol';
import './libraries/TransferHelper.sol';
/// @title Algebra community fee vault
/// @notice Community fee from pools is sent here, if it is enabled
/// @dev Role system is used to withdraw tokens
/// @dev Version: Algebra Integral 1.2
contract AlgebraCommunityVault is IAlgebraCommunityVault {
  
  address public immutable vaultFactory;
  address public immutable pool;

  modifier onlyWithdrawer() {
    require(
      msg.sender == IAlgebraVaultFactory(vaultFactory).algebraFeeManager() || 
      IAlgebraVaultFactory(vaultFactory).hasRole(IAlgebraVaultFactory(vaultFactory).COMMUNITY_FEE_WITHDRAWER_ROLE(), msg.sender), 
      'only withdrawer'
      );
    _;
  }


  constructor(address _vaultFactory, address _pool) {
    vaultFactory = _vaultFactory;
    pool = _pool;
  }

  /// @inheritdoc IAlgebraCommunityVault
  function withdraw(address token, uint256 amount) external override onlyWithdrawer {
    (uint16 _algebraFee, address _algebraFeeReceiver, address _communityFeeReceiver, uint16 _communityFee) = _readAndVerifyWithdrawSettings();
    _withdraw(token, _communityFeeReceiver, amount, _algebraFee, _algebraFeeReceiver, _communityFee);
  }

  /// @inheritdoc IAlgebraCommunityVault
  function withdrawTokens(WithdrawTokensParams[] calldata params) external override onlyWithdrawer {
    uint256 paramsLength = params.length;
    (uint16 _algebraFee, address _algebraFeeReceiver, address _communityFeeReceiver, uint16 _communityFee) = _readAndVerifyWithdrawSettings();

    unchecked {
      for (uint256 i; i < paramsLength; ++i) _withdraw(params[i].token, _communityFeeReceiver, params[i].amount, _algebraFee, _algebraFeeReceiver, _communityFee);
    }
  }

  function _readAndVerifyWithdrawSettings() private view returns (uint16 _algebraFee, address _algebraFeeReceiver, address _communityFeeReceiver, uint16 _communityFee) {
    (_algebraFee, _algebraFeeReceiver, _communityFeeReceiver) = (IAlgebraVaultFactory(vaultFactory).algebraFee(), IAlgebraVaultFactory(vaultFactory).algebraFeeReceiver(), IAlgebraVaultFactory(vaultFactory).communityFeeReceiver());
    _communityFee = IAlgebraVaultFactory(vaultFactory).communityFee();
    if (_communityFee != 0) require(_communityFeeReceiver != address(0), 'invalid community fee receiver');
    if (_algebraFee != 0) require(_algebraFeeReceiver != address(0), 'invalid algebra fee receiver');
  }

  function _withdraw(address token, address _communityFeeReceiver, uint256 amount, uint16 _algebraFee, address _algebraFeeReceiver, uint16 _communityFee) private {
    uint256 withdrawAmount = amount;

    if (_algebraFee != 0) {
      uint256 algebraFeeAmount = FullMath.mulDivRoundingUp(withdrawAmount, _algebraFee, IAlgebraVaultFactory(vaultFactory).ALGEBRA_FEE_DENOMINATOR());
      withdrawAmount -= algebraFeeAmount;
      SafeTransfer.safeTransfer(token, _algebraFeeReceiver, algebraFeeAmount);
      emit AlgebraTokensWithdrawal(token, _algebraFeeReceiver, algebraFeeAmount);
    }

    if (_communityFee != 0) {
      uint256 communityFeeAmount = FullMath.mulDivRoundingUp(withdrawAmount, _communityFee, IAlgebraVaultFactory(vaultFactory).ALGEBRA_FEE_DENOMINATOR());
      withdrawAmount -= communityFeeAmount;
      SafeTransfer.safeTransfer(token, _communityFeeReceiver, communityFeeAmount);
      emit CommunityTokensWithdrawal(token, _communityFeeReceiver, communityFeeAmount);
    }

    address feeDistributor = IAlgebraVaultFactory(vaultFactory).getFeeDistributorForPool(pool);
    if(feeDistributor != address(0) && withdrawAmount != 0) {
      TransferHelper.safeApprove(token, feeDistributor, withdrawAmount);
      IIncentiveManager(feeDistributor).notifyRewardAmount(token, withdrawAmount);
      TransferHelper.safeApprove(token, feeDistributor, 0);
      emit TokensWithdrawal(token, feeDistributor, withdrawAmount);
    } else {
      SafeTransfer.safeTransfer(token, _communityFeeReceiver, withdrawAmount);
      emit TokensWithdrawal(token, _communityFeeReceiver, withdrawAmount);
    }
  }
}
