// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "../interfaces/IBalanceTracker.sol";
import "../interfaces/events/BalanceUpdateEvent.sol";
import "../interfaces/events/EventWrapper.sol";
import "../interfaces/events/EventReceiver.sol";
import "../interfaces/events/DelegationEnabled.sol";
import "../interfaces/events/DelegationDisabled.sol";

contract BalanceTracker is EventReceiver, IBalanceTracker, Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant EVENT_TYPE_DEPOSIT = bytes32("Deposit");
    bytes32 public constant EVENT_TYPE_TRANSFER = bytes32("Transfer");
    bytes32 public constant EVENT_TYPE_SLASH = bytes32("Slash");
    bytes32 public constant EVENT_TYPE_WITHDRAW = bytes32("Withdraw");
    bytes32 public constant EVENT_TYPE_WITHDRAWALREQUEST = bytes32("Withdrawal Request");
    bytes32 public constant EVENT_TYPE_DELEGATION_ENABLED = bytes32("DelegationEnabled");
    bytes32 public constant EVENT_TYPE_DELEGATION_DISABLED = bytes32("DelegationDisabled");

    // user account address -> token address -> balance
    mapping(address => mapping(address => TokenBalance)) public accountTokenBalances;
    // token address -> total tracked balance
    mapping(address => uint256) public totalTokenBalances;

    // account -> delegatedTo
    mapping(address => address) public delegatedTo;

    EnumerableSet.AddressSet private supportedTokenAddresses;

    //solhint-disable-next-line no-empty-blocks, func-visibility
    function initialize(address eventProxy) public initializer {
        __Ownable_init_unchained();
        EventReceiver.init(eventProxy);
    }

    function getBalance(address account, address[] calldata tokens)
        external
        view
        override
        returns (TokenBalance[] memory userBalances)
    {
        userBalances = new TokenBalance[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            // Return 0 if account has delegated
            if (delegatedTo[account] != address(0)) {
                userBalances[i] = TokenBalance({token: tokens[i], amount: 0});
            } else {
                userBalances[i] = accountTokenBalances[account][tokens[i]];
            }
        }

        return userBalances;
    }

    function getActualBalance(address account, address[] calldata tokens)
        external
        view
        override
        returns (TokenBalance[] memory userBalances)
    {
        userBalances = new TokenBalance[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            userBalances[i] = accountTokenBalances[account][tokens[i]];
        }

        return userBalances;
    }

    function setBalance(SetTokenBalance[] calldata balances) external override onlyOwner {
        for (uint256 i = 0; i < balances.length; i++) {
            SetTokenBalance calldata balance = balances[i];
            updateBalance({
                account: balance.account,
                token: balance.token,
                amount: balance.amount,
                stateSync: false
            });
        }
    }

    function updateBalance(
        address account,
        address token,
        uint256 amount,
        bool stateSync
    ) private {
        require(token != address(0), "INVALID_TOKEN_ADDRESS");
        require(supportedTokenAddresses.contains(token), "UNSUPPORTED_ADDRESS");
        require(account != address(0), "INVALID_ACCOUNT_ADDRESS");

        TokenBalance memory userTokenBalance = accountTokenBalances[account][token];

        // stateSync updates balances on an ongoing basis, whereas setBalance is only
        // allowed to update balances that have not been set before
        if (stateSync || userTokenBalance.token == address(0)) {
            //Update the total based on the individual amounts
            _updateTotalTokenBalance(token, userTokenBalance.amount, amount);

            accountTokenBalances[account][token] = TokenBalance({token: token, amount: amount});
            if (delegatedTo[account] != address(0)) {
                //Delegated balance, back out individual and apply new balance
                uint256 delegatedAmt = accountTokenBalances[delegatedTo[account]][token].amount;
                delegatedAmt = delegatedAmt.sub(userTokenBalance.amount).add(amount);
                accountTokenBalances[delegatedTo[account]][token] = TokenBalance({
                    token: token,
                    amount: delegatedAmt
                });
            }

            emit BalanceUpdate(account, token, amount, stateSync, true);
        } else {
            // setBalance may trigger this event if it tries to update the balance
            // of an already set user-token key
            emit BalanceUpdate(account, token, amount, false, false);
        }
    }

    function _delegate(
        address token,
        address from,
        address to
    ) private {
        require(from != address(0), "INVALID_FROM");
        require(token != address(0), "INVALID_TOKEN");

        TokenBalance memory balanceToTransfer = accountTokenBalances[from][token];

        //See if we need to back it out of an existing delegation
        if (delegatedTo[from] != address(0)) {
            TokenBalance memory oldDelegateBal = accountTokenBalances[delegatedTo[from]][token];
            oldDelegateBal.amount = oldDelegateBal.amount.sub(balanceToTransfer.amount);
            accountTokenBalances[delegatedTo[from]][token] = oldDelegateBal;
        }

        if (to != address(0)) {
            //Apply the existing balance to the new account
            TokenBalance memory newDelegateBal = accountTokenBalances[to][token];
            newDelegateBal.amount = newDelegateBal.amount.add(balanceToTransfer.amount);
            newDelegateBal.token = token;
            accountTokenBalances[to][token] = newDelegateBal;
        }

        delegatedTo[from] = to;

        emit BalanceDelegated(token, from, to);
    }

    function _delegateAll(
        address from,
        address to,
        bytes32 functionId
    ) private {
        // so far, only vote delegtion impacts BalanceTracker 
        if (functionId == "voting") {
            uint256 length = supportedTokenAddresses.length();
            for (uint256 i = 0; i < length; i++) {
                address token = supportedTokenAddresses.at(i);
                _delegate(token, from, to);
            }
        }
    }

    function getSupportedTokens()
        external
        view
        override
        returns (address[] memory supportedTokensArray)
    {
        uint256 supportedTokensLength = supportedTokenAddresses.length();
        supportedTokensArray = new address[](supportedTokensLength);

        for (uint256 i = 0; i < supportedTokensLength; i++) {
            supportedTokensArray[i] = supportedTokenAddresses.at(i);
        }
        return supportedTokensArray;
    }

    function addSupportedTokens(address[] calldata tokensToSupport) external override onlyOwner {
        require(tokensToSupport.length > 0, "NO_TOKENS");

        for (uint256 i = 0; i < tokensToSupport.length; i++) {
            require(tokensToSupport[i] != address(0), "ZERO_ADDRESS");

            require(supportedTokenAddresses.add(tokensToSupport[i]), "ADD_FAIL");
        }
        emit SupportedTokensAdded(tokensToSupport);
    }

    function removeSupportedTokens(address[] calldata tokensToSupport) external override onlyOwner {
        require(tokensToSupport.length > 0, "NO_TOKENS");

        for (uint256 i = 0; i < tokensToSupport.length; i++) {
            require(tokensToSupport[i] != address(0), "ZERO_ADDRESS");

            require(supportedTokenAddresses.remove(tokensToSupport[i]), "REMOVE_FAIL");
        }
        emit SupportedTokensRemoved(tokensToSupport);
    }

    function _updateTotalTokenBalance(
        address token,
        uint256 oldAmount,
        uint256 newBalance
    ) private {
        uint256 currentTotalBalance = totalTokenBalances[token];
        uint256 updatedTotalBalance = currentTotalBalance.sub(oldAmount).add(newBalance);
        totalTokenBalances[token] = updatedTotalBalance;
    }

    function _onBalanceChange(bytes calldata data) private {
        BalanceUpdateEvent memory balanceUpdate = abi.decode(data, (BalanceUpdateEvent));

        updateBalance({
            account: balanceUpdate.account,
            token: balanceUpdate.token,
            amount: balanceUpdate.amount,
            stateSync: true
        });
    }

    function _onDelegationEnabled(bytes calldata data) private {
        DelegationEnabled memory delegation = abi.decode(data, (DelegationEnabled));
        _delegateAll(delegation.from, delegation.to, delegation.functionId);
    }

    function _onDelegationDisabled(bytes calldata data) private {
        DelegationDisabled memory delegation = abi.decode(data, (DelegationDisabled));
        _delegateAll(delegation.from, address(0), delegation.functionId);
    }

    function _onEventReceive(
        address,
        bytes32 eventType,
        bytes calldata data
    ) internal virtual override {
        if (
            eventType == EVENT_TYPE_DEPOSIT ||
            eventType == EVENT_TYPE_TRANSFER ||
            eventType == EVENT_TYPE_WITHDRAW ||
            eventType == EVENT_TYPE_SLASH ||
            eventType == EVENT_TYPE_WITHDRAWALREQUEST
        ) {
            _onBalanceChange(data);
        } else if (eventType == EVENT_TYPE_DELEGATION_ENABLED) {
            _onDelegationEnabled(data);
        } else if (eventType == EVENT_TYPE_DELEGATION_DISABLED) {
            _onDelegationDisabled(data);
        } else {
            revert("INVALID_EVENT_TYPE");
        }
    }
}
