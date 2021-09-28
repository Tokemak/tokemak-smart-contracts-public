// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "../fxPortal/IFxMessageProcessor.sol";

interface IEventProxy is IFxMessageProcessor {

    struct DestinationsBySenderAndEventType {
        address sender;
        bytes32 eventType;
        address[] destinations;
    }

    event SenderRegistrationChanged(address sender, bool allowed);
    event DestinationRegistered(address sender, address destination);
    event DestinationUnregistered(address sender, address destination);
    event SenderRegistered(address sender, bool allowed);
    event RegisterDestinations(DestinationsBySenderAndEventType[]);
    event UnregisterDestination(address sender, address l2Endpoint, bytes32 eventType);
    event EventSent(bytes32 eventType, address sender, address destination, bytes data);
    event SetGateway(bytes32 name, address gateway);

    /// @notice Toggles a senders ability to send an event through the contract
    /// @param sender Address of sender
    /// @param allowed Allowed to send event
    /// @dev Contracts should call as themselves, and so it will be the contract addresses registered here
    function setSenderRegistration(address sender, bool allowed) external;

    /// @notice For a sender/eventType, register destination contracts that should receive events
    /// @param destinationsBySenderAndEventType Destinations specifies all the destinations for a given sender/eventType combination
    /// @dev this COMPLETELY REPLACES all destinations for the sender/eventType
    function registerDestinations(DestinationsBySenderAndEventType[] memory destinationsBySenderAndEventType) external;

    /// @notice retrieves all the registered destinations for a sender/eventType key
    function getRegisteredDestinations(address sender, bytes32 eventType) external view returns(address[] memory);

    /// @notice For a sender, unregister destination contracts on Polygon
    /// @param sender Address of sender
    function unregisterDestination(address sender, address l2Endpoint, bytes32 eventType) external;
}