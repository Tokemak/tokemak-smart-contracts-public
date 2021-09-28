// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

struct CycleRolloverEvent {
    bytes32 eventSig;
    uint256 cycleIndex;
    uint256 blockNumber;
}