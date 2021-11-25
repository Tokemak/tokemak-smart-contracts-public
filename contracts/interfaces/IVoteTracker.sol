// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "./events/IEventReceiver.sol";
import "./structs/TokenBalance.sol";
import "./structs/UserVotePayload.sol";

interface IVoteTracker is IEventReceiver {
    //Collpased simple settings
    struct VoteTrackSettings {
        address balanceTrackerAddress;
        uint256 voteEveryBlockLimit;
        uint256 lastProcessedEventId;
        bytes32 voteSessionKey;
    }

    //Colapsed NETWORK settings
    struct NetworkSettings {
        bytes32 domainSeparator;
        uint256 chainId;
    }

    struct UserVotes {
        UserVoteDetails details;
        UserVoteAllocationItem[] votes;
    }

    struct UserVoteDetails {
        uint256 totalUsedVotes;
        uint256 totalAvailableVotes;
    }

    struct SystemVotes {
        SystemVoteDetails details;
        SystemAllocation[] votes;
    }

    struct SystemVoteDetails {
        bytes32 voteSessionKey;
        uint256 totalVotes;
    }

    struct SystemAllocation {
        address token;
        bytes32 reactorKey;
        uint256 totalVotes;
    }

    struct EIP712Domain {
        string name;
        string version;
        uint256 chainId;
        address verifyingContract;
    }

    struct VoteTokenMultipler {
        address token;
        uint256 multiplier;
    }

    struct VotingLocation {
        address token;
        bytes32 key;
    }

    enum SignatureType {
        INVALID,
        EIP712,
        ETHSIGN
    }

    struct Signature {
        // How to validate the signature.
        SignatureType signatureType;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    event UserAggregationUpdated(address account);
    event UserVoted(address account, UserVotes votes);
    event WithdrawalRequestApplied(address account, UserVotes postApplicationVotes);
    event VoteSessionRollover(bytes32 newKey, SystemVotes votesAtRollover);
    event BalanceTrackerAddressSet(address contractAddress);
    event ProxySubmitterSet(address[] accounts, bool allowed);
    event ReactorKeysSet(bytes32[] allValidKeys);
    event VoteMultipliersSet(VoteTokenMultipler[] multipliers);
    event ProxyRateLimitSet(uint256 voteEveryBlockLimit);
    event SigningChainIdSet(uint256 chainId);

    /// @notice Get the current nonce an account should use to vote with
    /// @param account Account to query
    /// @return nonce Nonce that shoul dbe used to vote with
    function userNonces(address account) external returns (uint256 nonce);

    /// @notice Get the last block a user submitted a vote through a relayer
    /// @param account Account to check
    /// @return blockNumber
    function lastUserProxyVoteBlock(address account) external returns (uint256 blockNumber);

    /// @notice Check if an account is currently configured as a relayer
    /// @param account Account to check
    /// @return allowed
    function proxySubmitters(address account) external returns (bool allowed);

    /// @notice Get the tokens that are currently used to calculate voting power
    /// @return tokens
    function getVotingTokens() external view returns (address[] memory tokens);

    /// @notice Allows backfilling of current balance
    /// @param userVotePayload Users vote percent breakdown
    /// @param signature Account signature
    function vote(UserVotePayload calldata userVotePayload, Signature memory signature) external;

    function voteDirect(UserVotePayload memory userVotePayload) external;

    /// @notice Updates the users and system aggregation based on their current balances
    /// @param accounts Accounts that just had their balance updated
    /// @dev Should call back to BalanceTracker to pull that accounts current balance
    function updateUserVoteTotals(address[] memory accounts) external;

    /// @notice Set the contract that should be used to lookup user balances
    /// @param contractAddress Address of the contract
    function setBalanceTrackerAddress(address contractAddress) external;

    /// @notice Toggle the accounts that are currently used to relay votes and thus subject to rate limits
    /// @param submitters Relayer account array
    /// @param allowed Add or remove the account
    function setProxySubmitters(address[] calldata submitters, bool allowed) external;

    /// @notice Get the reactors we are currently accepting votes for
    /// @return reactorKeys Reactor keys we are currently accepting
    function getReactorKeys() external view returns (bytes32[] memory reactorKeys);

    /// @notice Set the reactors that we are currently accepting votes for
    /// @param reactorKeys Array for token+key where token is the underlying ERC20 for the reactor and key is asset-default|exchange
    /// @param allowed Add or remove the keys from use
    /// @dev Only current reactor keys will be returned from getSystemVotes()
    function setReactorKeys(VotingLocation[] memory reactorKeys, bool allowed) external;

    /// @notice Changes the chain id users will sign their vote messages on
    /// @param chainId Chain id the users will be connected to when they vote
    function setSigningChainId(uint256 chainId) external;

    /// @notice Current votes for the account
    /// @param account Account to get votes for
    /// @return Votes for the current account
    function getUserVotes(address account) external view returns (UserVotes memory);

    /// @notice Current total votes for the system
    /// @return systemVotes
    function getSystemVotes() external view returns (SystemVotes memory systemVotes);

    /// @notice Get the current voting power for an account
    /// @param account Account to check
    /// @return Current voting power
    function getMaxVoteBalance(address account) external view returns (uint256);

    /// @notice Given a set of token balances, determine the voting power given current multipliers
    /// @param balances Token+Amount to use for calculating votes
    /// @return votes Voting power
    function getVotingPower(TokenBalance[] memory balances) external view returns (uint256 votes);

    /// @notice Set the voting power tokens get
    /// @param multipliers Token and multipliers to set. Multipliers should have 18 precision
    function setVoteMultiplers(VoteTokenMultipler[] memory multipliers) external;

    /// @notice Set the rate limit for using the proxy submission route
    /// @param voteEveryBlockLimit Minimum block gap between proxy submissions
    function setProxyRateLimit(uint256 voteEveryBlockLimit) external;

    /// @notice Returns general settings and current system vote details
    function getSettings() external view returns (VoteTrackSettings memory settings);
}
