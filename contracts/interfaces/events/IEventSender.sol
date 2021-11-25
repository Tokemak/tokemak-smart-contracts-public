// SPDX-License-Identifier: MIT

pragma solidity >= 0.6.11;
pragma experimental ABIEncoderV2;

import "./Destinations.sol";

interface IEventSender {

    event DestinationsSet(address fxStateSender, address destinationOnL2);
    event EventSendSet(bool eventSendSet);

    function setDestinations(address fxStateSender, address destinationOnL2) external;

    function setEventSend(bool eventSendSet) external;
}