// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "./IEventReceiver.sol";

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

/// @title Base contract for receiving events through our Event Proxy
abstract contract EventReceiver is Initializable, IEventReceiver {
    address public eventProxy;

    event ProxyAddressSet(address proxyAddress);

    function init(address eventProxyAddress) public initializer {
        require(eventProxyAddress != address(0), "INVALID_ROOT_PROXY");

        _setEventProxyAddress(eventProxyAddress);
    }

    /// @notice Receive an encoded event from a contract on a different chain
    /// @param sender Contract address of sender on other chain
    /// @param eventType Encoded event type
    /// @param data Event Event data
    function onEventReceive(
        address sender,
        bytes32 eventType,
        bytes calldata data
    ) external override {
        require(msg.sender == eventProxy, "EVENT_PROXY_ONLY");

        _onEventReceive(sender, eventType, data);
    }

    /// @notice Implemented by child contracts to process events
    /// @param sender Contract address of sender on other chain
    /// @param eventType Encoded event type
    /// @param data Event Event data
    function _onEventReceive(
        address sender,
        bytes32 eventType,
        bytes calldata data
    ) internal virtual;

    /// @notice Configures the contract that can send events to this contract
    /// @param eventProxyAddress New sender address
    function _setEventProxyAddress(address eventProxyAddress) private {
        eventProxy = eventProxyAddress;

        emit ProxyAddressSet(eventProxy);
    }
}
