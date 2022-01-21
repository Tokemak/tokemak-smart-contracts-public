// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

/// @notice Vote payload to be submitted to Vote Tracker
struct UserVotePayload {
    address account;
    bytes32 voteSessionKey;
    uint256 nonce;
    uint256 chainId;
    uint256 totalVotes;
    UserVoteAllocationItem[] allocations;
}

/// @notice Individual allocation to an asset, exchange, or asset-pair
struct UserVoteAllocationItem {
    bytes32 reactorKey;
    uint256 amount; //18 Decimals
}
