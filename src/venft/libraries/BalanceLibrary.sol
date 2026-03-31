// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IVeNFT} from "../../interfaces/IVeNFT.sol";
import {SafeCastLibrary} from "./SafeCastLibrary.sol";

/// @title SafeCast Library
/// @author velodrome.finance
/// @notice Safely convert unsigned and signed integers without overflow / underflow
library BalanceLibrary {

    using SafeCastLibrary for uint256;
    using SafeCastLibrary for int128;

    uint256 internal constant WEEK = 1 weeks;


    function getPastUserPointArrIndex(
        mapping(uint256 => uint256) storage _userPointEpoch,
        mapping(uint256 => IVeNFT.UserPoint[1000000000]) storage _userPointHistory,
        uint256 _tokenId,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 _userEpoch = _userPointEpoch[_tokenId];
        if (_userEpoch == 0) return 0;
        // First check most recent point history of user's epoch
        if (_userPointHistory[_tokenId][_userEpoch].ts <= _timestamp) return (_userEpoch);
        // Return first epoch if second epoch's timestamp is greater than the first
        if (_userPointHistory[_tokenId][1].ts > _timestamp) return 0;

        uint256 min = 0;
        uint256 max = _userEpoch;
        // Binary search
        while (max > min) {
            uint256 mid = max - (max - min) / 2;
            IVeNFT.UserPoint storage userPoint = _userPointHistory[_tokenId][mid];
            if (userPoint.ts == _timestamp) {
                return mid;
            } else if (userPoint.ts < _timestamp) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    function getPastEpochPointArrIndex(
        uint256 _epoch,
        mapping(uint256 => IVeNFT.EpochPoint) storage _pointHistory,
        uint256 _timestamp
    ) internal view returns (uint256) {
        if (_epoch == 0) return 0;
        // First check most recent point history of global epoch
        if (_pointHistory[_epoch].ts <= _timestamp) return (_epoch);
        // Return first epoch if second epoch's timestamp is greater than the first
        if (_pointHistory[1].ts > _timestamp) return 0;

        uint256 min = 0;
        uint256 max = _epoch;
        // Binary search
        while (max > min) {
            uint256 mid = max - (max - min) / 2;
            IVeNFT.EpochPoint storage epochPoint = _pointHistory[mid];
            if (epochPoint.ts == _timestamp) {
                return mid;
            } else if (epochPoint.ts < _timestamp) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    function balanceOfNFTAt(
        mapping(uint256 => uint256) storage _userPointEpoch,
        mapping(uint256 => IVeNFT.UserPoint[1000000000]) storage _userPointHistory,
        uint256 _tokenId,
        uint256 _timestamp
    ) external view returns (uint256) {
        uint256 _epoch = getPastUserPointArrIndex(_userPointEpoch, _userPointHistory, _tokenId, _timestamp);
        // first epoch is an empty point
        if (_epoch == 0) return 0;
        IVeNFT.UserPoint memory epochPoint = _userPointHistory[_tokenId][_epoch];
        if (epochPoint.permanent != 0) {
            return epochPoint.permanent;
        } else {
            epochPoint.bias -= epochPoint.slope * (_timestamp - epochPoint.ts).toInt128();
            if (epochPoint.bias < 0) {
                epochPoint.bias = 0;
            }
            return epochPoint.bias.toUint256();
        }
    }

    function supplyAt(
        mapping(uint256 => int128) storage _slopeChanges,
        mapping(uint256 => IVeNFT.EpochPoint) storage _epochPointHistory,
        uint256 _epoch,
        uint256 _timestamp
    ) external view returns (uint256) {
        uint256 epoch_ = getPastEpochPointArrIndex(_epoch, _epochPointHistory, _timestamp);
        // first epoch is an empty point
        if (epoch_ == 0) return 0;
        IVeNFT.EpochPoint memory _point = _epochPointHistory[epoch_];
        int128 bias = _point.bias;
        int128 slope = _point.slope;
        uint256 ts = _point.ts;
        uint256 t_i = (ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) { // 255 covers 4.9 years
            t_i += WEEK;
            int128 dSlope = 0;
            if (t_i > _timestamp) {
                t_i = _timestamp;
            } else {
                dSlope = _slopeChanges[t_i];
            }
            bias -= slope * (t_i - ts).toInt128();
            if (t_i == _timestamp) {
                break;
            }
            slope += dSlope;
            ts = t_i;
        }

        if (bias < 0) {
            bias = 0;
        }
        return bias.toUint256() + _point.permanentLockBalance;
    }
    
}
