// SPDX-License-Identifier: MIT

pragma solidity >= 0.6.11;

import "../../fxPortal/IFxStateSender.sol";

struct Destinations {
    IFxStateSender fxStateSender;
    address destinationOnL2;
}