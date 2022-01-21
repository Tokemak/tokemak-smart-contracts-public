// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

/// @title Interface for Balancer Labs On Chain Registry
/// @dev https://docs.balancer.fi/v/v1/smart-contracts/on-chain-registry
interface IBalancerRegistry {
    /// @notice Retrieve array of pool addresses for token pair. Ordered by liquidity if previously sorted. Max of n pools returned where n=limit.
    function getBestPoolsWithLimit(
        address,
        address,
        uint256
    ) external view returns (address[] memory);

    /// @notice Retrieve array of pool addresses for token pair. Ordered by liquidity if previously sorted. Max of 32 pools returned.
    function getBestPools(address fromToken, address destToken)
        external
        view
        returns (address[] memory pools);
}
