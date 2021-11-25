// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

struct UserInfo {
    uint256 amount;
    int256 rewardDebt;
}

struct PoolInfo {
    uint128 accSushiPerShare;
    uint64 lastRewardBlock;
    uint64 allocPoint;
}

interface IMasterChefV2 {

    function deposit(uint256 pid, uint256 amount, address to) external;

    function withdraw(uint256 pid, uint256 amount, address to) external;

    function userInfo(uint256 pid, address user) external returns (uint256, uint256);
}