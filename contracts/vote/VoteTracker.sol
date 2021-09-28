// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "../interfaces/IVoteTracker.sol";
import "../interfaces/IBalanceTracker.sol";

import "../interfaces/events/EventWrapper.sol";
import "../interfaces/events/CycleRolloverEvent.sol";
import "../interfaces/events/BalanceUpdateEvent.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/events/EventReceiver.sol";

import "hardhat/console.sol";

//TODO: Add Pausable for incoming votes

contract VoteTracker is EventReceiver, IVoteTracker, Ownable, Pausable {
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
        keccak256(
            "UserVoteAllocationItem(bytes32 reactorKey,uint256 amount)"
        );

    bytes32 public constant DOMAIN_NAME = keccak256("Tokemak Voting");
    bytes32 public constant DOMAIN_VERSION = keccak256("1");

    bytes32 public constant EVENT_TYPE_DEPOSIT = bytes32("Deposit");
    bytes32 public constant EVENT_TYPE_TRANSFER = bytes32("Transfer");
    bytes32 public constant EVENT_TYPE_SLASH = bytes32("Slash");
    bytes32 public constant EVENT_TYPE_WITHDRAW = bytes32("Withdraw");
    bytes32 public constant EVENT_TYPE_CYCLECOMPLETE = bytes32("Cycle Complete");

    //Normally these would only be generated during construction against the current chain id
    //However, our users will be signing while connected to mainnet so we'll need a diff
    //chainId than we're running on. We'll validate the intended chain in the message itself
    //against the actual chain the contract is running on.    
    bytes32 public currentDomainSeparator;    
    uint256 public currentSigningChainId;

    //For when the users decide to connect to the network and submit directly
    //We'll want domain to be the actual chain
    // solhint-disable var-name-mixedcase
    bytes32 public immutable NETWORK_DOMAIN_SEPARATOR;
    uint256 public immutable NETWORK_CHAIN_ID;
    // solhint-enable var-name-mixedcase    

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
    constructor(
        address eventProxy,
        bytes32 initialVoteSession,
        address balanceTracker,
        uint256 signingOnChain,
        VoteTokenMultipler[] memory voteTokens
    ) EventReceiver(eventProxy) {
        require(initialVoteSession.length > 0, "INVALID_SESSION_KEY");      
        require(voteTokens.length > 0, "NO_VOTE_TOKENS");

        settings.voteSessionKey = initialVoteSession;
        settings.balanceTrackerAddress = balanceTracker;

        setVoteMultiplers(voteTokens);
        
        setSigningChainId(signingOnChain);

        NETWORK_CHAIN_ID = _getChainID();
        NETWORK_DOMAIN_SEPARATOR = _buildDomainSeparator(_getChainID());
    }

    /// @notice Vote for the assets and reactors you wish to see liquidity deployed for
    /// @param userVotePayload Users vote percent breakdown
    /// @param v v from secp256k1 signature
    /// @param r r from secp256k1 signature
    /// @param s s from secp256k1 signature
    function vote(UserVotePayload memory userVotePayload, uint8 v, bytes32 r, bytes32 s) external override whenNotPaused {
        uint256 domainChain = _getChainID();

        require(domainChain == userVotePayload.chainId, "INVALID_PAYLOAD_CHAIN");

        // Rate limiting when using our proxy apis
        // Users can only submit every X blocks
        if (proxySubmitters[msg.sender]) {
            require(lastUserProxyVoteBlock[userVotePayload.account].add(settings.voteEveryBlockLimit) < block.number, "TOO_FREQUENT_VOTING");
            lastUserProxyVoteBlock[userVotePayload.account] = block.number;
            domainChain = currentSigningChainId;
        } 

        // Validate the signer is the account the votes are on behalf of
        address signatureSigner = _hash(domainChain, userVotePayload).recover(v, r, s);
        require(signatureSigner == userVotePayload.account, "MISMATCH_SIGNER");

        require(settings.voteSessionKey == userVotePayload.voteSessionKey, "NOT_CURRENT_VOTE_SESSION");        
        require(userNonces[userVotePayload.account] == userVotePayload.nonce, "INVALID_NONCE");

        uint256 maxAvailableVotes = getMaxVoteBalance(userVotePayload.account);
        require(userVotePayload.totalVotes <= maxAvailableVotes, "NOT_ENOUGH_VOTES");

        // Should we want to do delegate voting in the future we can add an
        // adapter in front of the BalanceTracker and change the destination of messages
        // from mainnet

        // Ensure the message cannot be replayed
        userNonces[userVotePayload.account] = userNonces[userVotePayload.account].add(1);

        //Ensure all the percents add up to 1
        //Make use of the loop and deconstruct the array for saving
        uint256 summedVotes = 0;                
        for(uint256 i = 0; i < userVotePayload.allocations.length; i++) {
            //Ensure where they are voting is allowed
            require(allowedreactorKeys.contains(userVotePayload.allocations[i].reactorKey), "PLACEMENT_NOT_ALLOWED");

            //Sum percents
            summedVotes = summedVotes.add(userVotePayload.allocations[i].amount);          
        }
        require(summedVotes == userVotePayload.totalVotes, "VOTE_TOTAL_MISMATCH");

        emit UserVoted(userVotePayload.account, userVotePayload);

        // Data is validated and persisted, update the totals
        _updateUserVoteTotals(userVotePayload.account, userVotePayload.totalVotes, userVotePayload.allocations, maxAvailableVotes, false);
    }

    /// @notice Updates the users and system aggregation based on their current balances
    /// @param account Account that just had their balance updated
    /// @dev Should call back to BalanceTracker to pull that accounts current balance
    function updateUserVoteTotals(address account) public override {
        require(account != address(0), "INVALID_ADDRESS");

        bytes32[] memory keys = userVoteKeys[account];
        UserVoteAllocationItem[] memory placements = new UserVoteAllocationItem[](keys.length);
        for(uint256 i = 0; i < keys.length; i++) {
            placements[i] = UserVoteAllocationItem({
                reactorKey: keys[i],
                amount: userVoteItems[account][keys[i]]
            });
        }
        uint256 maxAvailableVotes = getMaxVoteBalance(account);

        //Call here emits
       _updateUserVoteTotals(account, userVoteDetails[account].totalUsedVotes, placements, maxAvailableVotes, true);
    } 

    function getUserVotes(address account) external override view returns(UserVotes memory) {
        bytes32[] memory keys = userVoteKeys[account];
        UserVoteAllocationItem[] memory placements = new UserVoteAllocationItem[](keys.length);
        for(uint256 i = 0; i < keys.length; i++) {
            placements[i] = UserVoteAllocationItem({
                reactorKey: keys[i],
                amount: userVoteItems[account][keys[i]]
            });
        }

        return UserVotes({
            votes: placements,
            details: userVoteDetails[account]
        });
    }

    function getSystemVotes() public override view returns(SystemVotes memory systemVotes) {
        uint256 placements = allowedreactorKeys.length();
        SystemAllocation[] memory votes = new SystemAllocation[](placements);
        uint256 totalVotes = 0;
        for(uint256 i = 0; i < placements; i++) {
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

    function getMaxVoteBalance(address account) public override view returns (uint256) {
        TokenBalance[] memory balances = IBalanceTracker(settings.balanceTrackerAddress).getBalance(account, votingTokens);
        return _getVotingPower(balances);
    }

    function getVotingPower(TokenBalance[] memory balances) external override view returns (uint256 votes) {
        votes = _getVotingPower(balances);
    }

    /// @notice Set the contract that should be used to lookup user balances
    /// @param contractAddress Address of the contract
    function setBalanceTrackerAddress(address contractAddress) external override onlyOwner {
        settings.balanceTrackerAddress = contractAddress;

        emit BalanceTrackerAddressSet(contractAddress);
    }

    function setProxySubmitters(address[] calldata submitters, bool allowed) public override onlyOwner {

        uint256 length = submitters.length;
        for(uint256 i = 0; i < length; i++) {
            proxySubmitters[submitters[i]] = allowed;
        }

        emit ProxySubmitterSet(submitters, allowed);
    }

    function setReactorKeys(VotingLocation[] memory reactorKeys, bool allowed) public override onlyOwner {
        uint256 length = reactorKeys.length;

        for(uint256 i = 0; i < length; i++) {
            if (allowed) {
                allowedreactorKeys.add(reactorKeys[i].key);
                placementTokens[reactorKeys[i].key] = reactorKeys[i].token;
            } else {
                allowedreactorKeys.remove(reactorKeys[i].key);
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
            for(uint256 i = votingTokenLength; i > 0; i--) {            
                votingTokens.pop();
            }
        }

        for(uint256 i = 0; i < multipliers.length; i++) {
            voteMultipliers[multipliers[i].token] = multipliers[i].multiplier;
            votingTokens.push(multipliers[i].token);
        }

        emit VoteMultipliersSet(multipliers);
    }

    function getVotingTokens() external override view returns (address[] memory tokens) {
        uint256 length = votingTokens.length;
        tokens = new address[](length);
        for(uint256 i = 0; i < length; i++) {
            tokens[i] = votingTokens[i];
        }
    }

    function setProxyRateLimit(uint256 voteEveryBlockLimit) external override onlyOwner {
        settings.voteEveryBlockLimit = voteEveryBlockLimit;

        emit ProxyRateLimitSet(voteEveryBlockLimit);
    }

    function getReactorKeys() public override view returns (bytes32[] memory reactorKeys) {
        uint256 length = allowedreactorKeys.length();
        reactorKeys = new bytes32[](length);

        for(uint256 i = 0; i < length; i++) {
            reactorKeys[i] = allowedreactorKeys.at(i);
        }
    }

    function getSettings() external override view returns (VoteTrackSettings memory) {
        return settings;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unPause() external onlyOwner {
        _unpause();
    }

    function _onEventReceive(address, bytes32 eventType, bytes calldata data) internal override virtual  {
        
        if (eventType == EVENT_TYPE_CYCLECOMPLETE) {
            _onCycleRollover(data);
        } else if (eventType == EVENT_TYPE_DEPOSIT || eventType == EVENT_TYPE_TRANSFER || eventType == EVENT_TYPE_WITHDRAW || eventType == EVENT_TYPE_SLASH) {
            _onBalanceChange(data);
        } else {
            revert("INVALID_EVENT_TYPE");
        } 
    }

    function _getVotingPower(TokenBalance[] memory balances) private view returns (uint256 votes) {
        for(uint256 i = 0; i < balances.length; i++) {
            votes = votes.add(balances[i].amount.mul(voteMultipliers[balances[i].token]).div(ONE_WITH_EIGHTEEN_PRECISION));
        }        
    }

    function _onCycleRollover(bytes calldata data) private {
        SystemVotes memory lastAgg = getSystemVotes();
        CycleRolloverEvent memory e = abi.decode(data, (CycleRolloverEvent));
        bytes32 newKey = bytes32(e.cycleIndex);
        settings.voteSessionKey = newKey;
        emit VoteSessionRollover(newKey, lastAgg);
    }

    function _onBalanceChange(bytes calldata data) private {
        BalanceUpdateEvent memory e = abi.decode(data, (BalanceUpdateEvent));
        updateUserVoteTotals(e.account);
    }

    function _updateUserVoteTotals(address account, uint256 totalUsedVotes, UserVoteAllocationItem[] memory newPlacements, uint256 maxAvailableVotes, bool calcAmounts) private {

        //Grab their current aggregation and back it out of the system aggregation
        bytes32[] storage currentAccountVoteKeys = userVoteKeys[account];
        uint256 userAggLength = currentAccountVoteKeys.length;

        if (userAggLength > 0) {            
            for(uint256 i = userAggLength; i > 0; i--) {                                            
                uint256 amt = userVoteItems[account][currentAccountVoteKeys[i-1]];
                systemAggregations[currentAccountVoteKeys[i-1]] = systemAggregations[currentAccountVoteKeys[i-1]].sub(amt);                
                currentAccountVoteKeys.pop();
            }
        }

        //Compute new aggregations        
        uint256 maxVotesToUse = Math.min(maxAvailableVotes, totalUsedVotes);
        if (maxVotesToUse > 0) {
            for(uint256 x = 0; x < newPlacements.length; x++) {

                if (calcAmounts) {
                    uint256 votedAmt = maxVotesToUse.mul(newPlacements[x].amount.mul(ONE_WITH_EIGHTEEN_PRECISION).div(totalUsedVotes)).div(ONE_WITH_EIGHTEEN_PRECISION);
                    newPlacements[x].amount = votedAmt;
                }
                //Update user aggregation
                userVoteItems[account][newPlacements[x].reactorKey] = newPlacements[x].amount;
                userVoteKeys[account].push(newPlacements[x].reactorKey);
                
                //Update system aggregation
                systemAggregations[newPlacements[x].reactorKey] = systemAggregations[newPlacements[x].reactorKey].add(newPlacements[x].amount);            
            }
        }

        //Update users aggregation details
        userVoteDetails[account] = UserVoteDetails({
            totalUsedVotes: maxVotesToUse,
            totalAvailableVotes: maxAvailableVotes
        });

        emit UserAggregationUpdated(account);
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
        } else if (domainChain == NETWORK_CHAIN_ID) {
            return NETWORK_DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator(domainChain);
        }
    }

    function _buildDomainSeparator(uint256 chainId) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                DOMAIN_NAME,
                DOMAIN_VERSION,
                chainId,
                address(this)
            )
        );
    }

    function _hash(uint256 domainChain, UserVotePayload memory userVotePayload) private view returns (bytes32) {
        bytes32 x =  
            keccak256(
                abi.encodePacked(
                    EIP191_HEADER,
                    _domainSeparatorV4(domainChain),
                    _hashUserVotePayload(userVotePayload)    
                )
            );
        return x;
    }

    function _hashUserVotePayload(UserVotePayload memory userVote) private pure returns (bytes32) {
        bytes32[] memory encodedVotes = new bytes32[](userVote.allocations.length);
        for(uint256 ix = 0; ix < userVote.allocations.length; ix++) {
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
                    keccak256(abi.encodePacked(
                        encodedVotes
                    ))
                )
            );
    }

    function _hashUserVoteAllocationItem(UserVoteAllocationItem memory voteAllocation) private pure returns (bytes32) {
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