// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

struct BalanceUpdateEvent {
    bytes32 eventSig;
    address account;
    address token;
    uint256 amount;
}
