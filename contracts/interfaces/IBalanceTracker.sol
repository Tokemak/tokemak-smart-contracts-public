// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "./events/IEventReceiver.sol";
import "./structs/TokenBalance.sol";

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
    event BalanceUpdate(address account, address token, uint256 amount, bool stateSynced, bool applied);

    /// @notice Retrieve the current balances for the supplied account and tokens
    function getBalance(address account, address[] calldata tokens) external view returns (TokenBalance[] memory userBalances);

    /// @notice Allows backfilling of current balance
    /// @dev onlyOwner. Only allows unset balances to be updated
    function setBalance(SetTokenBalance[] calldata balances) external;
}