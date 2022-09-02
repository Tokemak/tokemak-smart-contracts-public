// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "../interfaces/ICycleRolloverTracker.sol";
import "../interfaces/events/EventReceiver.sol";
import "../interfaces/events/CycleRolloverEvent.sol";

//solhint-disable not-rely-on-time 
contract CycleRolloverTracker is ICycleRolloverTracker, EventReceiver {
    bytes32 public constant EVENT_TYPE_CYCLE_COMPLETE = bytes32("Cycle Complete");
    bytes32 public constant EVENT_TYPE_CYCLE_START = bytes32("Cycle Rollover Start");

    constructor(address eventProxy) public {
        EventReceiver.init(eventProxy);
    }

    function _onCycleRolloverStart(bytes calldata data) private {
        CycleRolloverEvent memory cycleRolloverEvent = abi.decode(data, (CycleRolloverEvent));
        emit CycleRolloverStart(block.timestamp, cycleRolloverEvent.cycleIndex, cycleRolloverEvent.timestamp);
    }

    function _onCycleRolloverComplete(bytes calldata data) private {
        CycleRolloverEvent memory cycleRolloverEvent = abi.decode(data, (CycleRolloverEvent));
        emit CycleRolloverComplete(block.timestamp, cycleRolloverEvent.cycleIndex, cycleRolloverEvent.timestamp);
    }

    function _onEventReceive(
        address,
        bytes32 eventType,
        bytes calldata data
    ) internal virtual override {
        if (eventType == EVENT_TYPE_CYCLE_START) {
            _onCycleRolloverStart(data);
        } else if (eventType == EVENT_TYPE_CYCLE_COMPLETE) {
            _onCycleRolloverComplete(data);
        } else {
            revert("INVALID_EVENT_TYPE");
        }
    }
}
