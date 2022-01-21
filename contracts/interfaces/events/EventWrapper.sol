// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

/// @notice Simple structure for events sent to Governance layer
struct EventWrapper {
    bytes32 eventType;
    bytes data;
}
