// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "../interfaces/IEventProxy.sol";
import "../interfaces/events/EventWrapper.sol";
import "../interfaces/events/IEventReceiver.sol";
import "../fxPortal/IFxStateSender.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract EventProxy is Initializable, IEventProxy, Ownable {
    /// @dev FxPortal's FxChild
    // solhint-disable-next-line var-name-mixedcase
    address public STATE_SENDER;

    // sender => enabled. Only enabled senders emit events. Others are noop.
    mapping(address => bool) public registeredSenders;

    uint256 public lastProcessedStateId;

    // sender => event => Destination[]
    mapping(address => mapping(bytes32 => address[])) public destinations;

    function initialize(address stateSender) public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();

        STATE_SENDER = stateSender;
    }

    function setSenderRegistration(address _sender, bool _allowed) external override onlyOwner {
        require(_sender != address(0), "INVALID_ADDRESS");
        registeredSenders[_sender] = _allowed;

        emit SenderRegistered(_sender, _allowed);
    }

    function registerDestinations(
        DestinationsBySenderAndEventType[] memory destinationsBySenderAndEventType
    ) external override onlyOwner {
        for (uint256 i = 0; i < destinationsBySenderAndEventType.length; i++) {
            DestinationsBySenderAndEventType memory config = destinationsBySenderAndEventType[i];
            require(config.sender != address(0), "INVALID_SENDER_ADDRESS");
            require(config.eventType != "", "INVALID_EVENT_TYPE");
            require(config.destinations.length != 0, "MUST_SPECIFY_AT_LEAST_ONE_DESTINATION");

            // consider improving efficiency by overwriting existing
            // slots and pushing/popping if we need more/less
            delete destinations[config.sender][config.eventType];

            for (uint256 y = 0; y < config.destinations.length; y++) {
                require(config.destinations[y] != address(0), "INVALID_L2_ENDPOINT_ADDRESS");
                destinations[config.sender][config.eventType].push(config.destinations[y]);
            }
        }

        emit RegisterDestinations(destinationsBySenderAndEventType);
    }

    function getRegisteredDestinations(address sender, bytes32 eventType)
        external
        view
        override
        returns (address[] memory)
    {
        return destinations[sender][eventType];
    }

    /// @notice Recieves payload from mainnet
    /// @param stateId Counter from the mainnet Polygon contract that is forwarding the event. Nonce.
    /// @param rootMessageSender Sender from mainnet
    /// @param data Event we are sending
    /// @dev Manager will be sending events with current vote session key
    function processMessageFromRoot(
        uint256 stateId,
        address rootMessageSender,
        bytes calldata data
    ) external override {
        require(msg.sender == STATE_SENDER, "NOT_STATE_SENDER");
        require(stateId > lastProcessedStateId, "EVENT_ALREADY_PROCESSED");
        require(registeredSenders[rootMessageSender], "INVALID_ROOT_SENDER");

        //Ensure messages can't be replayed
        lastProcessedStateId = stateId;

        //Must have sent something, at least an event type, so we know how to route
        require(data.length > 0, "NO_DATA");

        //Determine event type
        bytes32 eventType = abi.decode(data[:32], (bytes32));
        require(eventType != "", "INVALID_EVENT_TYPE");

        address[] memory targetDestinations = destinations[rootMessageSender][eventType];
        for (uint256 i = 0; i < targetDestinations.length; i++) {
            address destination = targetDestinations[i];
            IEventReceiver(destination).onEventReceive(rootMessageSender, eventType, data);

            emit EventSent(eventType, rootMessageSender, destination, data);
        }
    }

    // TODO: this should take the index for the targeted destination so we don't have to loop
    function unregisterDestination(
        address _sender,
        address _l2Endpoint,
        bytes32 _eventType
    ) external override onlyOwner {
        address[] storage destination = destinations[_sender][_eventType];

        uint256 index = 256**2 - 1;
        for (uint256 i = 0; i < destination.length; i++) {
            if (destination[i] == _l2Endpoint) {
                index = i;
                break;
            }
        }

        require(index < 256**2 - 1, "DESTINATION_DOES_NOT_EXIST");

        for (uint256 i = index; i < destination.length - 1; i++) {
            destination[i] = destination[i + 1];
        }
        destination.pop();

        emit UnregisterDestination(_sender, _l2Endpoint, _eventType);
    }
}
