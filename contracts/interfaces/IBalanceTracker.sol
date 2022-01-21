// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "./events/IEventReceiver.sol";
import "./structs/TokenBalance.sol";

/**
 *   @title Accounts for every balance the user has in the Pools
 *   and the Staking contracts. It is used to support the Vote Tracker
 *   in determining voting power
 */
interface IBalanceTracker is IEventReceiver {
    struct SetTokenBalance {
        address account;
        address token;
        uint256 amount;
    }

    /// @param account User address
    /// @param token Token address
    /// @param amount User balance set for the user-token key
    /// @param stateSynced True if the event is from the L1 to L2 state sync. False if backfill
    /// @param applied False if the update was not actually recorded. Only applies to backfill updates that are skipped
    event BalanceUpdate(
        address account,
        address token,
        uint256 amount,
        bool stateSynced,
        bool applied
    );

    /// @param tokens Tokens addresses that have been added
    event SupportedTokensAdded(address[] tokens);

    /// @param tokens Tokens addresses that have been removed
    event SupportedTokensRemoved(address[] tokens);

    /// @param from delegator
    /// @param to delegatee
    /// @param token token delegated
    event BalanceDelegated(address token, address from, address to);

    /// @notice get all tokens currently supported by the contract
    /// @return supportedTokensArray an array of supported token addresses
    function getSupportedTokens() external view returns (address[] memory supportedTokensArray);

    /// @notice adds tokens to support
    /// @param tokensToSupport an array of supported token addresses
    function addSupportedTokens(address[] calldata tokensToSupport) external;

    /// @notice removes tokens to support
    /// @param tokensToRemove an array of token addresses to remove from supported token
    function removeSupportedTokens(address[] calldata tokensToRemove) external;

    /// @notice Retrieve the current balances for the supplied account and tokens. Returned balance WILL respect delegation
    function getBalance(address account, address[] calldata tokens)
        external
        view
        returns (TokenBalance[] memory userBalances);

    /// @notice Retrieve the current balances for the supplied account and tokens. Returned balance WONT respect delegation
    function getActualBalance(address account, address[] calldata tokens)
        external
        view
        returns (TokenBalance[] memory userBalances);

    /// @notice Allows backfilling of current balance
    /// @dev onlyOwner. Only allows unset balances to be updated
    function setBalance(SetTokenBalance[] calldata balances) external;
}
