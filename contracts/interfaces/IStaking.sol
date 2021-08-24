// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

interface IStaking {

    struct StakingSchedule {
        uint256 cliff; // Duration in seconds before staking starts
        uint256 duration; // Seconds it takes for entire amount to stake
        uint256 interval; // Seconds it takes for a chunk to stake
        bool setup; //Just so we know its there        
        bool isActive; //Whether we can setup new stakes with the schedule
        uint256 hardStart; //Stakings will always start at this timestamp if set    
        bool isPublic; //Schedule can be written to by any account    
    }

    struct StakingScheduleInfo {
        StakingSchedule schedule;
        uint256 index;
    }

    struct StakingDetails {
        uint256 initial; //Initial amount of asset when stake was created, total amount to be staked before slashing
        uint256 withdrawn; //Amount that was staked and subsequently withdrawn
        uint256 slashed; //Amount that has been slashed        
        uint256 started; //Timestamp at which the stake started
        uint256 scheduleIx;
    }

    struct WithdrawalInfo {
        uint256 minCycleIndex;
        uint256 amount;
    }

    event ScheduleAdded(uint256 scheduleIndex, uint256 cliff, uint256 duration, uint256 interval, bool setup, bool isActive, uint256 hardStart);    
    event ScheduleRemoved(uint256 scheduleIndex);    
    event WithdrawalRequested(address account, uint256 amount);
    event WithdrawCompleted(address account, uint256 amount);    
    event Deposited(address account, uint256 amount, uint256 scheduleIx);
    event Slashed(address account, uint256 amount, uint256 scheduleIx);

    ///@notice Allows for checking of user address in permissionedDepositors mapping
    ///@param account Address of account being checked
    ///@return Boolean, true if address exists in mapping
    function permissionedDepositors(address account) external returns (bool);

    ///@notice Allows owner to set a multitude of schedules that an address has access to
    ///@param account User address
    ///@param userSchedulesIdxs Array of schedule indexes
    function setUserSchedules(address account, uint256[] calldata userSchedulesIdxs) external;

    ///@notice Allows owner to add schedule
    ///@param schedule A StakingSchedule struct that contains all info needed to make a schedule
    function addSchedule(StakingSchedule memory schedule) external;

    ///@notice Gets all info on all schedules
    ///@return retSchedules An array of StakingScheduleInfo struct
    function getSchedules() external view returns (StakingScheduleInfo[] memory retSchedules);

    ///@notice Allows owner to set a permissioned depositor
    ///@param account User address
    ///@param canDeposit Boolean representing whether user can deposit
    function setPermissionedDepositor(address account, bool canDeposit) external;

    ///@notice Allows owner to remove a schedule by schedule Index
    ///@param scheduleIndex A uint256 representing a schedule
    function removeSchedule(uint256 scheduleIndex) external;    

    ///@notice Allows a user to get the stakes of an account
    ///@param account Address that is being checked for stakes
    ///@return stakes StakingDetails array containing info about account's stakes
    function getStakes(address account) external view returns(StakingDetails[] memory stakes);

    ///@notice Gets total value staked for an address across all schedules
    ///@param account Address for which total stake is being calculated
    ///@return value uint256 total of account
    function balanceOf(address account) external view returns(uint256 value);

    ///@notice Returns amount available to withdraw for an account and schedule Index
    ///@param account Address that is being checked for withdrawals
    ///@param scheduleIndex Index of schedule that is being checked for withdrawals
    function availableForWithdrawal(address account, uint256 scheduleIndex) external view returns (uint256);

    ///@notice Returns unvested amount for certain address and schedule index
    ///@param account Address being checked for unvested amount
    ///@param scheduleIndex Schedule index being checked for unvested amount
    ///@return value Uint256 representing unvested amount
    function unvested(address account, uint256 scheduleIndex) external view returns(uint256 value);

    ///@notice Returns vested amount for address and schedule index
    ///@param account Address being checked for vested amount
    ///@param scheduleIndex Schedule index being checked for vested amount
    ///@return value Uint256 vested 
    function vested(address account, uint256 scheduleIndex) external view returns(uint256 value);

    ///@notice Allows user to deposit token to specific vesting / staking schedule
    ///@param amount Uint256 amount to be deposited
    ///@param scheduleIndex Uint256 representing schedule to user
    function deposit(uint256 amount, uint256 scheduleIndex) external;

    ///@notice Allows account to deposit on behalf of other account
    ///@param account Account to be deposited for
    ///@param amount Amount to be deposited
    ///@param scheduleIndex Index of schedule to be used for deposit
    function depositFor(address account, uint256 amount, uint256 scheduleIndex) external;

    ///@notice Allows permissioned depositors to deposit into custom schedule
    ///@param account Address of account being deposited for
    ///@param amount Uint256 amount being deposited
    ///@param schedule StakingSchedule struct containing details needed for new schedule
    function depositWithSchedule(address account, uint256 amount, StakingSchedule calldata schedule) external;

    ///@notice User can request withdrawal from staking contract at end of cycle
    ///@notice Performs checks to make sure amount <= amount available
    ///@param amount Amount to withdraw
    function requestWithdrawal(uint256 amount) external;

    ///@notice Allows for withdrawal after successful withdraw request and proper amount of cycles passed
    ///@param amount Amount to withdraw
    function withdraw(uint256 amount) external;

    function setScheduleStatus(uint256 scheduleIndex, bool activeBoolean) external;

    /// @notice Pause deposits on the pool. Withdraws still allowed
    function pause() external;

    /// @notice Unpause deposits on the pool.
    function unpause() external;
}
