// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

interface IEventEmitter {

    //For the Pools and such to inherit from

    event EventProxyAddressSet(address proxyAddress);

    function eventProxyAddress() external view returns (address proxyAddress);

    /// @notice Sets the event proxy address
    /// @param proxyAddress Address of the event proxy to send the event    
    function setEventProxyAddress(address proxyAddress) external;
}