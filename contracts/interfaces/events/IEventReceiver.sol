// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

interface IEventReceiver {

    function onEventReceive(address sender, bytes32 eventType, bytes calldata data) external;
}