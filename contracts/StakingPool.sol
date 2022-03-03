// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./access/Ownable.sol";
import "./access/ReentrancyGuard.sol";
import "./tokens/SafeBEP20.sol";

contract StakingPool is Ownable, ReentrancyGuard {
    using SafeBEP20 for IBEP20;

    struct UserInfo {
        uint256 amount;                 // The amount of tokens the user has staked
        uint256 rewardDebt;             // Reward debt for the user
        uint256 tokenWithdrawalDate;    // The date the user can withdraw their tokens
    }

    bool    public isInitialized;       // Flag if the pool has been initialized
    uint256 public accTokenPerShare;    // How many tokens are accured per share
    uint256 public startBlock;          // Block when rewards start
    uint256 public bonusEndBlock;       // Block when rewards end
    uint256 public lastRewardBlock;     // Block when pool was last updated
    uint256 public rewardPerBlock;      // How many tokens are rewarded per block
    uint256 public minimumStakingTime;  // How long someone must be staked in order to receive rewards
    uint256 public PRECISION_FACTOR;    // The precision factor

    IBEP20  public stakedToken;         // Token that is staked
    IBEP20  public rewardToken;         // Token that is distributed for rewards
    address public treasury;            // The treasury address

    mapping(address => UserInfo) public userInfo;   // User information for each staked user

    // Events for notifications of things
    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event NewRewardPerBlock(uint256 rewardPerBlock);
    event RewardsStop(uint256 blockNumber);
    event Withdraw(address indexed user, uint256 amount);
    event WithdrawEarly(address indexed user, uint256 amountWithdrawn, uint256 forfeitedRewards);

    // Constructor for passing the basic contract parameters
    constructor (address _stakedToken, address _rewardToken, address _treasury, uint256 _minimumStakingTime) {
        stakedToken = IBEP20(_stakedToken);
        rewardToken = IBEP20(_rewardToken);
        treasury = _treasury;
        minimumStakingTime = _minimumStakingTime;

        uint256 decimalsRewardToken = uint256(rewardToken.decimals());
        require(decimalsRewardToken < 30, "Decimals must be less than 30");

        PRECISION_FACTOR = uint256(10**(uint256(30) - decimalsRewardToken));
    }

    // Modifier to ensure the user is passed the minimum stake time, or trying to withdraw 0 tokens
    modifier canWithdraw(uint _amount) {
        uint _withdrawalDate = userInfo[msg.sender].tokenWithdrawalDate;
        require((block.timestamp >= _withdrawalDate && _withdrawalDate > 0) || _amount == 0, 'Staking: Token is still locked, use #withdrawEarly to withdraw funds before the end of your staking period.');
        _;
    }

    // Function to initialize the contract parameters after deployment
    function initialize(uint _rewardPerBlock, uint _startBlock, uint _bonusEndBlock) public onlyOwner() {
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        lastRewardBlock = startBlock;
        isInitialized = true;
    }

    // Function for the owner to update the rewards per block
    function updateRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner() {
        require(block.number < startBlock, "Pool has started");
        rewardPerBlock = _rewardPerBlock;
        emit NewRewardPerBlock(_rewardPerBlock);
    }

    // Function for the owner to update start and end blocks
    function updateStartAndEndBlocks(uint256 _startBlock, uint256 _bonusEndBlock) external onlyOwner() {
        require(block.number < startBlock, "Pool has started");
        require(_startBlock < _bonusEndBlock, "New startBlock must be lower than new endBlock");
        require(block.number < _startBlock, "New startBlock must be higher than current block");

        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        lastRewardBlock = startBlock;
        emit NewStartAndEndBlocks(_startBlock, _bonusEndBlock);
    }

    // Function for the owner to cease reward distribution
    function stopReward() external onlyOwner() {
        bonusEndBlock = block.number;
    }

    // Function for the owner to do an emergency withdraw of the rewards token
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner() {
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

    // Function for the owner to recover any random token that were sent to the contract
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner() {
        require(_tokenAddress != address(stakedToken), "Cannot be staked token");
        require(_tokenAddress != address(rewardToken), "Cannot be reward token");
        IBEP20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);
        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    // Function to get the pending rewards for a user
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));
        if (block.number > lastRewardBlock && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 reward = multiplier * rewardPerBlock;
            uint256 adjustedTokenPerShare = accTokenPerShare + ((reward * PRECISION_FACTOR) / stakedTokenSupply);
            return ((user.amount * adjustedTokenPerShare) / PRECISION_FACTOR) - user.rewardDebt;
        } else {
            return ((user.amount * accTokenPerShare) / PRECISION_FACTOR) - user.rewardDebt;
        }
    }

    // Function to handle depositing staked tokens
    function deposit(uint256 _amount) external nonReentrant() { 
        UserInfo storage user = userInfo[msg.sender];
        _updatePool();

        if (user.amount > 0) {
            uint256 pending = ((user.amount * accTokenPerShare) / PRECISION_FACTOR) - user.rewardDebt;
            if (pending > 0) rewardToken.safeTransfer(address(msg.sender), pending);
        }

        if (_amount > 0) {
            user.tokenWithdrawalDate = block.timestamp + minimumStakingTime;
            uint256 startBalance = stakedToken.balanceOf(address(this));
            stakedToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 received = stakedToken.balanceOf(address(this)) - startBalance;
            user.amount = user.amount + received;
        }

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
        emit Deposit(msg.sender, _amount);
    }

    // Function for handling withdrawing tokens when passed the minimum stake time or trying to withdraw 0 tokens
    function withdraw(uint256 _amount) external nonReentrant() canWithdraw(_amount) {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");
        _updatePool();

        uint256 pending = ((user.amount * accTokenPerShare) / PRECISION_FACTOR) - user.rewardDebt;

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            stakedToken.safeTransfer(address(msg.sender), _amount);
            user.tokenWithdrawalDate = block.timestamp + minimumStakingTime;
        }

        if (pending > 0) rewardToken.safeTransfer(address(msg.sender), pending);
        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
        emit Withdraw(msg.sender, _amount);
    }

    // Function to withdraw tokens before the minimum stake time and forfeit any pending rewards to the treasury
    function withdrawEarly(uint256 _amount) external nonReentrant() {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");
        _updatePool();
        uint256 pending = ((user.amount * accTokenPerShare) / PRECISION_FACTOR) - user.rewardDebt;

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            stakedToken.safeTransfer(address(msg.sender), _amount);
            user.tokenWithdrawalDate = block.timestamp + minimumStakingTime;
        }

        if (pending > 0) rewardToken.safeTransfer(treasury, pending);
        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
        emit WithdrawEarly(msg.sender, _amount, pending);
    }

    // Function to do an emergency withdraw of staked tokens without accounting for rewards
    function emergencyWithdraw() external nonReentrant() {
        UserInfo storage user = userInfo[msg.sender];
        uint256 tokens = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        if (tokens > 0) stakedToken.safeTransfer(address(msg.sender), tokens);
        emit EmergencyWithdraw(msg.sender, tokens);
    }

    // Function to update the pool
    function _updatePool() private {
        if (block.number <= lastRewardBlock) {
            return;
        }

        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));

        if (stakedTokenSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        uint256 reward = multiplier * rewardPerBlock;
        accTokenPerShare = accTokenPerShare + ((reward * PRECISION_FACTOR) / stakedTokenSupply);
        lastRewardBlock = block.number;
    }

    // Function to get the multiplier
    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to - _from;
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock - _from;
        }
    }
}