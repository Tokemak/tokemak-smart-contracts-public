// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

/**
 *  @title Used to forward event coming from L1
 */
interface ICycleRolloverTracker {    
    event CycleRolloverStart(uint256 timestamp, uint256 indexed cycleIndex, uint256 l1Timestamp);
    event CycleRolloverComplete(uint256 timestamp, uint256 indexed cycleIndex, uint256 l1Timestamp);

}
