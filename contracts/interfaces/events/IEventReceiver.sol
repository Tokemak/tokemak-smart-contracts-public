// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

interface IEventReceiver {
    /// @notice Receive an encoded event from a contract on a different chain
    /// @param sender Contract address of sender on other chain
    /// @param eventType Encoded event type
    /// @param data Event Event data
    function onEventReceive(
        address sender,
        bytes32 eventType,
        bytes calldata data
    ) external;
}
