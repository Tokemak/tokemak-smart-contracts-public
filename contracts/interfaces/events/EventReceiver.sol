// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "./IEventReceiver.sol";

abstract contract EventReceiver is IEventReceiver {
    
    address public eventProxy;

    event ProxyAddressSet(address proxyAddress);

    constructor(address eventProxyAddress) {
        require(eventProxyAddress != address(0), "INVALID_ROOT_PROXY");   

        _setEventProxyAddress(eventProxyAddress);
    }

    function onEventReceive(address sender, bytes32 eventType, bytes calldata data) external override {
        require(msg.sender == eventProxy, "EVENT_PROXY_ONLY");

        _onEventReceive(sender, eventType, data);
    }

    //solhint-disable-next-line no-unused-vars
    function _onEventReceive(address sender, bytes32 eventType, bytes calldata data) internal virtual;
    
    function _setEventProxyAddress(address eventProxyAddress) private {
        eventProxy = eventProxyAddress;

        emit ProxyAddressSet(eventProxy);
    }
}