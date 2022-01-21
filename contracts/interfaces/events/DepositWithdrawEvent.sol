// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

/// @notice Internal tracking of balance changes during Staking contract interactions
struct DepositWithdrawEvent {
    address user;
    address token;
    uint256 amount;
}