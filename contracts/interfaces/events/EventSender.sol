// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./Destinations.sol";
import "./IEventSender.sol";

abstract contract EventSender is IEventSender {
        
    bool public eventSend;
    Destinations public destinations;

    modifier onEventSend() {
        if(eventSend) {
            _;
        }
    }

    modifier onlyEventSendControl() {
        require(canControlEventSend(), "CANNOT_CONTROL_EVENTS");
        _;
    }

    function setDestinations(address fxStateSender, address destinationOnL2) external virtual override onlyEventSendControl {
        require(fxStateSender != address(0), "INVALID_FX_ADDRESS");
        require(destinationOnL2 != address(0), "INVALID_DESTINATION_ADDRESS");

        destinations.fxStateSender = IFxStateSender(fxStateSender);
        destinations.destinationOnL2 = destinationOnL2;

        emit DestinationsSet(fxStateSender, destinationOnL2);
    }

    function setEventSend(bool eventSendSet) external virtual override onlyEventSendControl {
        eventSend = eventSendSet;

        emit EventSendSet(eventSendSet);
    }

    function canControlEventSend() internal view virtual returns (bool);

    function sendEvent(bytes memory data) internal virtual {
        require(address(destinations.fxStateSender) != address(0), "ADDRESS_NOT_SET");
        require(destinations.destinationOnL2 != address(0), "ADDRESS_NOT_SET");

        destinations.fxStateSender.sendMessageToChild(destinations.destinationOnL2, data);
    }
}