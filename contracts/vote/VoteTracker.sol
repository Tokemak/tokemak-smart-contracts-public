// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "../interfaces/IVoteTracker.sol";
import "../interfaces/IBalanceTracker.sol";

import "../interfaces/events/EventWrapper.sol";
import "../interfaces/events/CycleRolloverEvent.sol";
import "../interfaces/events/BalanceUpdateEvent.sol";

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/Math.sol";
import {PausableUpgradeable as Pausable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "../interfaces/events/EventReceiver.sol";
import "../interfaces/structs/UserVotePayload.sol";

contract VoteTracker is Initializable, EventReceiver, IVoteTracker, Ownable, Pausable {
    using ECDSA for bytes32;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant ONE_WITH_EIGHTEEN_PRECISION = 1_000_000_000_000_000_000;

    /// @dev EIP191 header for EIP712 prefix
    string public constant EIP191_HEADER = "\x19\x01";

    bytes32 public constant EIP712_DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    bytes32 public constant USER_VOTE_PAYLOAD_TYPEHASH =
        keccak256(
            "UserVotePayload(address account,bytes32 voteSessionKey,uint256 nonce,uint256 chainId,uint256 totalVotes,UserVoteAllocationItem[] allocations)UserVoteAllocationItem(bytes32 reactorKey,uint256 amount)"
        );

    bytes32 public constant USER_VOTE_ALLOCATION_ITEM_TYPEHASH =
        keccak256("UserVoteAllocationItem(bytes32 reactorKey,uint256 amount)");

    bytes32 public constant DOMAIN_NAME = keccak256("Tokemak Voting");
    bytes32 public constant DOMAIN_VERSION = keccak256("1");

    bytes32 public constant EVENT_TYPE_DEPOSIT = bytes32("Deposit");
    bytes32 public constant EVENT_TYPE_TRANSFER = bytes32("Transfer");
    bytes32 public constant EVENT_TYPE_SLASH = bytes32("Slash");
    bytes32 public constant EVENT_TYPE_WITHDRAW = bytes32("Withdraw");
    bytes32 public constant EVENT_TYPE_CYCLECOMPLETE = bytes32("Cycle Complete");
    bytes32 public constant EVENT_TYPE_VOTE = bytes32("Vote");
    bytes32 public constant EVENT_TYPE_WITHDRAWALREQUEST = bytes32("Withdrawal Request");

    //Normally these would only be generated during construction against the current chain id
    //However, our users will be signing while connected to mainnet so we'll need a diff
    //chainId than we're running on. We'll validate the intended chain in the message itself
    //against the actual chain the contract is running on.
    bytes32 public currentDomainSeparator;
    uint256 public currentSigningChainId;

    //For when the users decide to connect to the network and submit directly
    //We'll want domain to be the actual chain
    NetworkSettings public networkSettings;

    /// @dev All publically accessible but you can use getUserVotes() to pull it all together
    mapping(address => UserVoteDetails) public userVoteDetails;
    mapping(address => bytes32[]) public userVoteKeys;
    mapping(address => mapping(bytes32 => uint256)) public userVoteItems;

    /// @dev Stores the users next valid vote nonce
    mapping(address => uint256) public override userNonces;

    /// @dev Stores the last block during which a user voted through our proxy
    mapping(address => uint256) public override lastUserProxyVoteBlock;

    VoteTrackSettings public settings;

    address[] public votingTokens;
    mapping(address => uint256) public voteMultipliers;

    /// @dev Total of all user aggregations
    /// @dev getSystemAggregation() to reconstruct
    EnumerableSet.Bytes32Set private allowedreactorKeys;
    mapping(bytes32 => uint256) public systemAggregations;
    mapping(bytes32 => address) public placementTokens;

    mapping(address => bool) public override proxySubmitters;

    // solhint-disable-next-line func-visibility
    function initialize(
        address eventProxy,
        bytes32 initialVoteSession,
        address balanceTracker,
        uint256 signingOnChain,
        VoteTokenMultipler[] memory voteTokens
    ) public initializer {
        require(initialVoteSession.length > 0, "INVALID_SESSION_KEY");
        require(voteTokens.length > 0, "NO_VOTE_TOKENS");

        __Ownable_init_unchained();
        __Pausable_init_unchained();

        EventReceiver.init(eventProxy);

        settings.voteSessionKey = initialVoteSession;
        settings.balanceTrackerAddress = balanceTracker;

        setVoteMultiplers(voteTokens);

        setSigningChainId(signingOnChain);

        networkSettings.chainId = _getChainID();
        networkSettings.domainSeparator = _buildDomainSeparator(_getChainID());
    }

    /// @notice Vote for the assets and reactors you wish to see liquidity deployed for
    /// @param userVotePayload Users vote percent breakdown
    /// @param signature Account signature
    function vote(UserVotePayload memory userVotePayload, Signature memory signature)
        external
        override
        whenNotPaused
    {
        uint256 domainChain = _getChainID();

        require(domainChain == userVotePayload.chainId, "INVALID_PAYLOAD_CHAIN");

        // Rate limiting when using our proxy apis
        // Users can only submit every X blocks
        if (proxySubmitters[msg.sender]) {
            require(
                lastUserProxyVoteBlock[userVotePayload.account].add(settings.voteEveryBlockLimit) <
                    block.number,
                "TOO_FREQUENT_VOTING"
            );
            lastUserProxyVoteBlock[userVotePayload.account] = block.number;
            domainChain = currentSigningChainId;
        }

        // Validate the signer is the account the votes are on behalf of
        address signatureSigner = _hash(domainChain, userVotePayload, signature.signatureType)
            .recover(signature.v, signature.r, signature.s);
        require(signatureSigner == userVotePayload.account, "MISMATCH_SIGNER");

        _vote(userVotePayload);
    }

    function voteDirect(UserVotePayload memory userVotePayload) external override whenNotPaused {
        require(msg.sender == userVotePayload.account, "MUST_BE_SENDER");
        require(userVotePayload.chainId == networkSettings.chainId, "INVALID_PAYLOAD_CHAIN");

        _vote(userVotePayload);
    }

    /// @notice Updates the users and system aggregation based on their current balances
    /// @param accounts Accounts list that just had their balance updated
    /// @dev Should call back to BalanceTracker to pull that accounts current balance
    function updateUserVoteTotals(address[] memory accounts) public override {
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];

            require(account != address(0), "INVALID_ADDRESS");

            bytes32[] memory keys = userVoteKeys[account];
            uint256 maxAvailableVotes = getMaxVoteBalance(account);
            uint256 maxVotesToUse = Math.min(
                maxAvailableVotes,
                userVoteDetails[account].totalUsedVotes
            );

            //Grab their current aggregation and back it out of the system aggregation
            bytes32[] storage currentAccountVoteKeys = userVoteKeys[account];
            uint256 userAggLength = currentAccountVoteKeys.length;

            if (userAggLength > 0) {
                for (uint256 k = userAggLength; k > 0; k--) {
                    uint256 amt = userVoteItems[account][currentAccountVoteKeys[k - 1]];
                    systemAggregations[currentAccountVoteKeys[k - 1]] = systemAggregations[
                        currentAccountVoteKeys[k - 1]
                    ].sub(amt);
                    currentAccountVoteKeys.pop();
                }
            }

            //Compute new aggregations
            uint256 total = 0;
            if (maxVotesToUse > 0) {
                for (uint256 j = 0; j < keys.length; j++) {
                    UserVoteAllocationItem memory placement = UserVoteAllocationItem({
                        reactorKey: keys[j],
                        amount: userVoteItems[account][keys[j]]
                    });

                    placement.amount = maxVotesToUse.mul(placement.amount).div(
                        userVoteDetails[account].totalUsedVotes
                    );
                    total = total.add(placement.amount);

                    //Update user aggregation
                    userVoteItems[account][placement.reactorKey] = placement.amount;
                    userVoteKeys[account].push(placement.reactorKey);

                    //Update system aggregation
                    systemAggregations[placement.reactorKey] = systemAggregations[
                        placement.reactorKey
                    ].add(placement.amount);
                }
            } else {
                //If these values are left, then when the user comes back and tries to vote
                //again, the total used won't line up
                for (uint256 j = 0; j < keys.length; j++) {
                    userVoteItems[account][keys[j]] = 0;
                }
            }

            //Call here emits
            //Update users aggregation details
            userVoteDetails[account] = UserVoteDetails({
                totalUsedVotes: total,
                totalAvailableVotes: maxAvailableVotes
            });

            emit UserAggregationUpdated(account);
        }
    }

    function getUserVotes(address account) public view override returns (UserVotes memory) {
        bytes32[] memory keys = userVoteKeys[account];
        UserVoteAllocationItem[] memory placements = new UserVoteAllocationItem[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            placements[i] = UserVoteAllocationItem({
                reactorKey: keys[i],
                amount: userVoteItems[account][keys[i]]
            });
        }
        return UserVotes({votes: placements, details: userVoteDetails[account]});
    }

    function getSystemVotes() public view override returns (SystemVotes memory systemVotes) {
        uint256 placements = allowedreactorKeys.length();
        SystemAllocation[] memory votes = new SystemAllocation[](placements);
        uint256 totalVotes = 0;
        for (uint256 i = 0; i < placements; i++) {
            votes[i] = SystemAllocation({
                reactorKey: allowedreactorKeys.at(i),
                totalVotes: systemAggregations[allowedreactorKeys.at(i)],
                token: placementTokens[allowedreactorKeys.at(i)]
            });
            totalVotes = totalVotes.add(votes[i].totalVotes);
        }

        systemVotes = SystemVotes({
            details: SystemVoteDetails({
                voteSessionKey: settings.voteSessionKey,
                totalVotes: totalVotes
            }),
            votes: votes
        });
    }

    function getMaxVoteBalance(address account) public view override returns (uint256) {
        TokenBalance[] memory balances = IBalanceTracker(settings.balanceTrackerAddress).getBalance(
            account,
            votingTokens
        );
        return _getVotingPower(balances);
    }

    function getVotingPower(TokenBalance[] memory balances)
        external
        view
        override
        returns (uint256 votes)
    {
        votes = _getVotingPower(balances);
    }

    /// @notice Set the contract that should be used to lookup user balances
    /// @param contractAddress Address of the contract
    function setBalanceTrackerAddress(address contractAddress) external override onlyOwner {
        settings.balanceTrackerAddress = contractAddress;

        emit BalanceTrackerAddressSet(contractAddress);
    }

    function setProxySubmitters(address[] calldata submitters, bool allowed)
        public
        override
        onlyOwner
    {
        uint256 length = submitters.length;
        for (uint256 i = 0; i < length; i++) {
            proxySubmitters[submitters[i]] = allowed;
        }

        emit ProxySubmitterSet(submitters, allowed);
    }

    function setReactorKeys(VotingLocation[] memory reactorKeys, bool allowed)
        public
        override
        onlyOwner
    {
        uint256 length = reactorKeys.length;

        for (uint256 i = 0; i < length; i++) {
            if (allowed) {
                require(allowedreactorKeys.add(reactorKeys[i].key), "ADD_FAIL");
                placementTokens[reactorKeys[i].key] = reactorKeys[i].token;
            } else {
                require(allowedreactorKeys.remove(reactorKeys[i].key), "REMOVE_FAIL");
                delete placementTokens[reactorKeys[i].key];
            }
        }

        bytes32[] memory validKeys = getReactorKeys();

        emit ReactorKeysSet(validKeys);
    }

    function setSigningChainId(uint256 chainId) public override onlyOwner {
        currentSigningChainId = chainId;
        currentDomainSeparator = _buildDomainSeparator(chainId);

        emit SigningChainIdSet(chainId);
    }

    function setVoteMultiplers(VoteTokenMultipler[] memory multipliers) public override onlyOwner {
        uint256 votingTokenLength = votingTokens.length;
        if (votingTokenLength > 0) {
            for (uint256 i = votingTokenLength; i > 0; i--) {
                votingTokens.pop();
            }
        }

        for (uint256 i = 0; i < multipliers.length; i++) {
            voteMultipliers[multipliers[i].token] = multipliers[i].multiplier;
            votingTokens.push(multipliers[i].token);
        }

        emit VoteMultipliersSet(multipliers);
    }

    function getVotingTokens() external view override returns (address[] memory tokens) {
        uint256 length = votingTokens.length;
        tokens = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = votingTokens[i];
        }
    }

    function setProxyRateLimit(uint256 voteEveryBlockLimit) external override onlyOwner {
        settings.voteEveryBlockLimit = voteEveryBlockLimit;

        emit ProxyRateLimitSet(voteEveryBlockLimit);
    }

    function getReactorKeys() public view override returns (bytes32[] memory reactorKeys) {
        uint256 length = allowedreactorKeys.length();
        reactorKeys = new bytes32[](length);

        for (uint256 i = 0; i < length; i++) {
            reactorKeys[i] = allowedreactorKeys.at(i);
        }
    }

    function getSettings() external view override returns (VoteTrackSettings memory) {
        return settings;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _onEventReceive(
        address,
        bytes32 eventType,
        bytes calldata data
    ) internal virtual override {
        if (eventType == EVENT_TYPE_CYCLECOMPLETE) {
            _onCycleRollover(data);
        } else if (
            eventType == EVENT_TYPE_DEPOSIT ||
            eventType == EVENT_TYPE_TRANSFER ||
            eventType == EVENT_TYPE_WITHDRAW ||
            eventType == EVENT_TYPE_SLASH ||
            eventType == EVENT_TYPE_WITHDRAWALREQUEST
        ) {
            _onBalanceChange(eventType, data);
        } else if (eventType == EVENT_TYPE_VOTE) {
            _onEventVote(data);
        } else {
            revert("INVALID_EVENT_TYPE");
        }
    }

    function _removeUserVoteKey(address account, bytes32 reactorKey) internal whenNotPaused {
        uint256 i = 0;
        bool deleted = false;
        while (i < userVoteKeys[account].length && !deleted) {
            if (userVoteKeys[account][i] == reactorKey) {
                userVoteKeys[account][i] = userVoteKeys[account][userVoteKeys[account].length - 1];
                userVoteKeys[account].pop();
                deleted = true;
            }
            i++;
        }
    }

    function _vote(UserVotePayload memory userVotePayload) internal whenNotPaused {
        address account = userVotePayload.account;
        uint256 totalUsedVotes = userVoteDetails[account].totalUsedVotes;

        require(
            settings.voteSessionKey == userVotePayload.voteSessionKey,
            "NOT_CURRENT_VOTE_SESSION"
        );
        require(userNonces[account] == userVotePayload.nonce, "INVALID_NONCE");

        // Ensure the message cannot be replayed
        userNonces[userVotePayload.account] = userNonces[userVotePayload.account].add(1);

        for (uint256 i = 0; i < userVotePayload.allocations.length; i++) {
            bytes32 reactorKey = userVotePayload.allocations[i].reactorKey;
            uint256 amount = userVotePayload.allocations[i].amount;

            //Ensure where they are voting is allowed
            require(allowedreactorKeys.contains(reactorKey), "PLACEMENT_NOT_ALLOWED");

            // check if user has already voted for this reactor
            if (userVoteItems[account][reactorKey] > 0) {
                if (amount == 0) {
                    _removeUserVoteKey(account, reactorKey);
                }

                uint256 currentAmount = userVoteItems[account][reactorKey];

                // increase or decrease systemAggregations[reactorKey] by the difference between currentAmount and amount
                if (currentAmount > amount) {
                    systemAggregations[reactorKey] = systemAggregations[reactorKey].sub(
                        currentAmount - amount
                    );
                    totalUsedVotes = totalUsedVotes.sub(currentAmount - amount);
                } else if (currentAmount < amount) {
                    systemAggregations[reactorKey] = systemAggregations[reactorKey].add(
                        amount - currentAmount
                    );
                    totalUsedVotes = totalUsedVotes.add(amount - currentAmount);
                }
                userVoteItems[account][reactorKey] = amount;
            } else {
                userVoteKeys[account].push(reactorKey);
                userVoteItems[account][reactorKey] = amount;
                systemAggregations[reactorKey] = systemAggregations[reactorKey].add(amount);
                totalUsedVotes = totalUsedVotes.add(amount);
            }
        }

        require(totalUsedVotes == userVotePayload.totalVotes, "VOTE_TOTAL_MISMATCH");

        uint256 totalAvailableVotes = getMaxVoteBalance(account);
        require(totalUsedVotes <= totalAvailableVotes, "NOT_ENOUGH_VOTES");

        //Update users aggregation details
        userVoteDetails[account] = UserVoteDetails({
            totalUsedVotes: totalUsedVotes,
            totalAvailableVotes: totalAvailableVotes
        });

        UserVotes memory votes = getUserVotes(account);

        emit UserVoted(account, votes);
    }

    function _onEventVote(bytes calldata data) private {
        (, bytes memory e) = abi.decode(data, (bytes32, bytes));

        UserVotePayload memory userVotePayload = abi.decode(e, (UserVotePayload));

        uint256 domainChain = _getChainID();

        require(domainChain == userVotePayload.chainId, "INVALID_PAYLOAD_CHAIN");
        _vote(userVotePayload);
    }

    function _getVotingPower(TokenBalance[] memory balances) private view returns (uint256 votes) {
        for (uint256 i = 0; i < balances.length; i++) {
            votes = votes.add(
                balances[i].amount.mul(voteMultipliers[balances[i].token]).div(
                    ONE_WITH_EIGHTEEN_PRECISION
                )
            );
        }
    }

    function _onCycleRollover(bytes calldata data) private {
        SystemVotes memory lastAgg = getSystemVotes();
        CycleRolloverEvent memory e = abi.decode(data, (CycleRolloverEvent));
        bytes32 newKey = bytes32(e.cycleIndex);
        settings.voteSessionKey = newKey;
        emit VoteSessionRollover(newKey, lastAgg);
    }

    function _onBalanceChange(bytes32 eventType, bytes calldata data) private {
        BalanceUpdateEvent memory e = abi.decode(data, (BalanceUpdateEvent));
        address[] memory accounts = new address[](1);
        accounts[0] = e.account;

        updateUserVoteTotals(accounts);

        if (eventType == EVENT_TYPE_WITHDRAWALREQUEST) {
            UserVotes memory postVotes = getUserVotes(e.account);
            emit WithdrawalRequestApplied(e.account, postVotes);
        }
    }

    function _getChainID() private pure returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }

    function _domainSeparatorV4(uint256 domainChain) internal view virtual returns (bytes32) {
        if (domainChain == currentSigningChainId) {
            return currentDomainSeparator;
        } else if (domainChain == networkSettings.chainId) {
            return networkSettings.domainSeparator;
        } else {
            return _buildDomainSeparator(domainChain);
        }
    }

    function _buildDomainSeparator(uint256 chainId) private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    EIP712_DOMAIN_TYPEHASH,
                    DOMAIN_NAME,
                    DOMAIN_VERSION,
                    chainId,
                    address(this)
                )
            );
    }

    function _hash(
        uint256 domainChain,
        UserVotePayload memory userVotePayload,
        SignatureType signatureType
    ) private view returns (bytes32) {
        bytes32 x = keccak256(
            abi.encodePacked(
                EIP191_HEADER,
                _domainSeparatorV4(domainChain),
                _hashUserVotePayload(userVotePayload)
            )
        );

        if (signatureType == SignatureType.ETHSIGN) {
            x = x.toEthSignedMessageHash();
        }

        return x;
    }

    function _hashUserVotePayload(UserVotePayload memory userVote) private pure returns (bytes32) {
        bytes32[] memory encodedVotes = new bytes32[](userVote.allocations.length);
        for (uint256 ix = 0; ix < userVote.allocations.length; ix++) {
            encodedVotes[ix] = _hashUserVoteAllocationItem(userVote.allocations[ix]);
        }

        return
            keccak256(
                abi.encode(
                    USER_VOTE_PAYLOAD_TYPEHASH,
                    userVote.account,
                    userVote.voteSessionKey,
                    userVote.nonce,
                    userVote.chainId,
                    userVote.totalVotes,
                    keccak256(abi.encodePacked(encodedVotes))
                )
            );
    }

    function _hashUserVoteAllocationItem(UserVoteAllocationItem memory voteAllocation)
        private
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(
                    USER_VOTE_ALLOCATION_ITEM_TYPEHASH,
                    voteAllocation.reactorKey,
                    voteAllocation.amount
                )
            );
    }
}
