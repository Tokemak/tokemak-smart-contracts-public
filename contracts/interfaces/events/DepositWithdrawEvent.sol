// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

struct DepositWithdrawEvent {
    address user;
    address token;
    uint256 amount;
}