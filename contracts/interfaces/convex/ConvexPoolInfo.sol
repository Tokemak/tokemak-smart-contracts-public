// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

struct ConvexPoolInfo {
    address lptoken;
    address token;
    address gauge;
    address crvRewards;
    address stash;
    bool shutdown;
}
