// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// import { IFarming } from "./interfaces/IFarming.sol";
// import { IStrategy } from "./interfaces/IStrategy.sol";
// import { ITokenBonding } from "./interfaces/ITokenBonding.sol";
// import { IIncentiveVoting } from "./interfaces/IIncentiveVoting.sol";

// contract Farming is IFarming, ReentrancyGuard, Ownable {
//   using SafeERC20 for IERC20;

//   // Info of each user.
//   struct UserInfo {
//     uint256 shares;
//     uint256 rewardDebt;
//     uint256 adjustedAmount;
//     uint256 claimable;
//   }
//   // Info of each pool.
//   struct PoolInfo {
//     IERC20 token;
//     IStrategy strategy;
//     uint256 rewardsPerSecond;
//     uint256 adjustedSupply;
//     uint256 lastRewardTime; // Last second that reward distribution occurs.
//     uint256 accRewardPerShare; // Accumulated rewards per share, times 1e12. See below.
//   }

//   uint256 private constant WEEK = 1 weeks;

//   // Info of each pool.
//   // address[] public registeredTokens;
//   // mapping(address => PoolInfo) public poolInfo;
//   PoolInfo[] public override poolInfo; // Info of each pool.

//   // token => user => Info of each user that stakes LP tokens.
//   mapping(uint256 => mapping(address => UserInfo)) public userInfo;
//   // The timestamp when reward mining starts.
//   uint256 public immutable startTime;

//   // account earning rewards => receiver of rewards for this account
//   // if receiver is set to address(0), rewards are paid to the earner
//   // this is used to aid 3rd party contract integrations
//   mapping(address => address) public claimReceiver;

//   // when set to true, other accounts cannot call
//   // `deposit` or `claim` on behalf of an account
//   mapping(address => bool) public blockThirdPartyActions;

//   IERC20 public immutable rewardToken;
//   IIncentiveVoting public immutable incentiveVoting;
//   ITokenBonding public immutable tokenLocker;

//   event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
//   event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
//   event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
//   event ClaimedReward(
//     address indexed caller,
//     address indexed claimer,
//     address indexed receiver,
//     uint256 amount
//   );
//   event FeeClaimSuccess(address pool);
//   event FeeClaimRevert(address pool);

//   constructor(
//     IERC20 _rewardToken,
//     IIncentiveVoting _incentiveVoting,
//     ITokenBonding _tokenLocker
//   ) {
//     startTime = _incentiveVoting.startTime();
//     rewardToken = _rewardToken;
//     incentiveVoting = _incentiveVoting;
//     tokenLocker = _tokenLocker;
//   }

//   /**
//     @notice The current number of stakeable LP tokens
//   */
//   function poolLength() external view returns (uint256) {
//     return poolInfo.length;
//   }

//   /**
//     @notice Add a new token that may be staked within this contract
//     @dev Called by `IncentiveVoting` after a successful token approval vote
//   */
//   function addPool(
//     address _token,
//     address _strategy,
//     bool _withUpdate
//   ) external returns (bool) {
//     require(msg.sender == address(incentiveVoting), "Sender not incentiveVoting");
//     if (_withUpdate) {
//       massUpdatePools();
//     }
//     poolInfo.push(
//       PoolInfo({
//         token: IERC20(_token),
//         strategy: IStrategy(_strategy),
//         adjustedSupply: 0,
//         rewardsPerSecond: 0,
//         lastRewardTime: block.timestamp,
//         accRewardPerShare: 0
//       })
//     );
//     return true;
//   }

//   /**
//     @notice Set the claim receiver address for the caller
//     @dev When the claim receiver is not == address(0), all
//           emission claims are transferred to this address
//     @param _receiver Claim receiver address
//   */
//   function setClaimReceiver(address _receiver) external {
//     claimReceiver[msg.sender] = _receiver;
//   }

//   /**
//     @notice Allow or block third-party calls to deposit, withdraw
//             or claim rewards on behalf of the caller
//   */
//   function setBlockThirdPartyActions(bool _block) external {
//     blockThirdPartyActions[msg.sender] = _block;
//   }

//   // View function to see staked Want tokens on frontend.
//   function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
//     PoolInfo storage pool = poolInfo[_pid];
//     UserInfo storage user = userInfo[_pid][_user];

//     uint256 sharesTotal = pool.strategy.sharesTotal();
//     uint256 wantLockedTotal = pool.strategy.wantLockedTotal();
//     if (sharesTotal == 0) {
//       return 0;
//     }
//     return (user.shares * wantLockedTotal) / sharesTotal;
//   }

//   // Update reward variables for all pools. Be careful of gas spending!
//   function massUpdatePools() public {
//     uint256 length = poolInfo.length;
//     for (uint256 pid = 0; pid < length; ++pid) {
//       _updatePool(pid);
//     }
//   }

//   // Update reward variables of the given pool to be up-to-date.
//   function _updatePool(uint256 _pid) internal returns (uint256 accRewardPerShare) {
//     PoolInfo storage pool = poolInfo[_pid];
//     uint256 lastRewardTime = pool.lastRewardTime;
//     require(lastRewardTime > 0, "Invalid pool");
//     // NOTE: need review
//     if (block.timestamp <= lastRewardTime) {
//       return pool.accRewardPerShare;
//     }
//     (accRewardPerShare, pool.rewardsPerSecond) = _getRewardData(_pid);
//     pool.lastRewardTime = block.timestamp;
//     if (accRewardPerShare == 0) return pool.accRewardPerShare;
//     accRewardPerShare += pool.accRewardPerShare;
//     pool.accRewardPerShare = accRewardPerShare;
//     return accRewardPerShare;
//   }

//   /**
//     @notice Get the current number of unclaimed rewards for a user on one or more tokens
//     @param _user User to query pending rewards for
//     @param _pids Array of token addresses to query
//     @return uint256[] Unclaimed rewards
//   */
//   function claimableReward(address _user, uint256[] calldata _pids)
//     external
//     view
//     returns (uint256[] memory)
//   {
//     uint256[] memory claimable = new uint256[](_pids.length);
//     for (uint256 i = 0; i < _pids.length; i++) {
//       uint256 pid = _pids[i];
//       PoolInfo storage pool = poolInfo[pid];
//       UserInfo storage user = userInfo[pid][_user];
//       (uint256 accRewardPerShare, ) = _getRewardData(pid);
//       accRewardPerShare += pool.accRewardPerShare;
//       claimable[i] =
//         user.claimable +
//         (user.adjustedAmount * accRewardPerShare) /
//         1e12 -
//         user.rewardDebt;
//     }
//     return claimable;
//   }

//   // NOTE: need review
//   // Get updated reward data for the given token
//   function _getRewardData(uint256 _pid)
//     internal
//     view
//     returns (uint256 accRewardPerShare, uint256 rewardsPerSecond)
//   {
//     PoolInfo storage pool = poolInfo[_pid];
//     uint256 lpSupply = pool.adjustedSupply;
//     uint256 start = startTime;
//     uint256 currentWeek = (block.timestamp - start) / WEEK;

//     if (lpSupply == 0) {
//       return (0, incentiveVoting.getRewardsPerSecond(address(pool.token), currentWeek));
//     }

//     uint256 lastRewardTime = pool.lastRewardTime;
//     uint256 rewardWeek = (lastRewardTime - start) / WEEK;
//     rewardsPerSecond = pool.rewardsPerSecond;
//     uint256 reward;
//     uint256 duration;
//     // NOTE: need review
//     if (rewardWeek < currentWeek) {
//       while (rewardWeek < currentWeek) {
//         rewardWeek++;
//         uint256 nextRewardTime = rewardWeek * WEEK + start;
//         duration = nextRewardTime - lastRewardTime;
//         reward += duration * rewardsPerSecond;
//         rewardsPerSecond = incentiveVoting.getRewardsPerSecond(address(pool.token), rewardWeek);
//         lastRewardTime = nextRewardTime;
//       }
//     }

//     duration = block.timestamp - lastRewardTime;
//     reward += duration * rewardsPerSecond;
//     return ((reward * 1e12) / lpSupply, rewardsPerSecond);
//   }

//   function deposit(
//     uint256 _pid,
//     uint256 _wantAmt,
//     bool _claimRewards
//   ) public nonReentrant returns (uint256) {
//     require(_wantAmt > 0, "Cannot deposit zero");
//     address _userAddress = msg.sender;
//     uint256 _accRewardPerShare = _updatePool(_pid);
//     PoolInfo storage pool = poolInfo[_pid];
//     UserInfo storage user = userInfo[_pid][_userAddress];

//     uint256 pending;
//     if (user.adjustedAmount > 0) {
//       pending = (user.adjustedAmount * _accRewardPerShare) / 1e12 - user.rewardDebt;
//       if (_claimRewards) {
//         pending += user.claimable;
//         user.claimable = 0;
//         pending = _safeRewardTransfer(msg.sender, pending);
//       } else if (pending > 0) {
//         user.claimable += pending;
//         pending = 0;
//       }
//     }

//     pool.token.safeTransferFrom(_userAddress, address(this), _wantAmt);
//     pool.token.safeIncreaseAllowance(address(pool.strategy), _wantAmt);
//     uint256 sharesAdded = pool.strategy.deposit(_userAddress, _wantAmt);
//     user.shares += sharesAdded;

//     _updateLiquidityLimits(_userAddress, _pid, sharesAdded, _accRewardPerShare);
//     emit Deposit(_userAddress, _pid, _wantAmt);
//     return pending;
//   }

//   /**
//     @notice Withdraw LP tokens from the contract
//     @dev Also updates the caller's current boost
//     @param _pid LP token address to withdraw.
//     @param _wantAmt Amount of tokens to withdraw.
//     @param _claimRewards If true, also claim rewards earned on the token.
//     @return uint256 Claimed reward amount
//   */
//   function withdraw(
//     uint256 _pid,
//     uint256 _wantAmt,
//     bool _claimRewards
//   ) public nonReentrant returns (uint256) {
//     address _userAddress = msg.sender;
//     require(_wantAmt > 0, "Cannot withdraw zero");
//     uint256 accRewardPerShare = _updatePool(_pid);
//     PoolInfo storage pool = poolInfo[_pid];
//     UserInfo storage user = userInfo[_pid][_userAddress];

//     uint256 sharesTotal = pool.strategy.sharesTotal();

//     require(user.shares > 0, "user.shares is 0");
//     require(sharesTotal > 0, "sharesTotal is 0");

//     uint256 pending = (user.adjustedAmount * accRewardPerShare) / 1e12 - user.rewardDebt;
//     if (_claimRewards) {
//       pending += user.claimable;
//       user.claimable = 0;
//       pending = _safeRewardTransfer(_userAddress, pending);
//     } else if (pending > 0) {
//       user.claimable += pending;
//       pending = 0;
//     }
//     // Withdraw want tokens
//     uint256 amount = (user.shares * pool.strategy.wantLockedTotal()) / sharesTotal;
//     if (_wantAmt > amount) {
//       _wantAmt = amount;
//     }
//     uint256 sharesRemoved = pool.strategy.withdraw(_userAddress, _wantAmt);

//     if (sharesRemoved > user.shares) {
//       user.shares = 0;
//     } else {
//       user.shares -= sharesRemoved;
//     }

//     IERC20 token = pool.token;
//     uint256 wantBal = token.balanceOf(address(this));
//     if (wantBal < _wantAmt) {
//       _wantAmt = wantBal;
//     }
//     _updateLiquidityLimits(_userAddress, _pid, user.shares, accRewardPerShare);
//     token.safeTransfer(_userAddress, _wantAmt);

//     emit Withdraw(_userAddress, _pid, _wantAmt);
//     return pending;
//   }

//   function withdrawAll(uint256 _pid, bool _claimable) public nonReentrant returns (uint256) {
//     return withdraw(_pid, type(uint256).max, _claimable);
//   }

//   /**
//     @notice Claim pending rewards for one or more tokens for a user.
//     @dev Also updates the claimer's boost.
//     @param _user Address to claim rewards for. Reverts if the caller is not the
//                   claimer and the claimer has blocked third-party actions.
//     @param _pids Array of LP token addresses to claim for.
//     @return uint256 Claimed reward amount
//   */
//   function claim(address _user, uint256[] calldata _pids) external returns (uint256) {
//     if (msg.sender != _user) {
//       require(!blockThirdPartyActions[_user], "Cannot claim on behalf of this account");
//     }

//     // calculate claimable amount
//     uint256 pending;
//     for (uint256 i = 0; i < _pids.length; i++) {
//       uint256 pid = _pids[i];
//       uint256 accRewardPerShare = _updatePool(pid);
//       UserInfo storage user = userInfo[pid][_user];
//       uint256 rewardDebt = (user.adjustedAmount * accRewardPerShare) / 1e12;
//       pending += user.claimable + rewardDebt - user.rewardDebt;
//       user.claimable = 0;
//       _updateLiquidityLimits(_user, pid, user.shares, accRewardPerShare);
//     }
//     return _safeRewardTransfer(_user, pending);
//   }

//   // NOTE: need review
//   function _updateLiquidityLimits(
//     address _user,
//     uint256 _pid,
//     uint256 _depositAmount,
//     uint256 _accRewardPerShare
//   ) internal {
//     PoolInfo storage pool = poolInfo[_pid];
//     uint256 userWeight = tokenLocker.userWeight(_user);
//     uint256 adjustedAmount = (_depositAmount * 40) / 100;
//     if (userWeight > 0) {
//       uint256 sharesTotal = pool.strategy.sharesTotal();
//       uint256 totalWeight = tokenLocker.totalWeight();
//       uint256 boost = (((sharesTotal * userWeight) / totalWeight) * 60) / 100;
//       adjustedAmount += boost;
//       if (adjustedAmount > _depositAmount) {
//         adjustedAmount = _depositAmount;
//       }
//     }
//     UserInfo storage user = userInfo[_pid][_user];
//     uint256 newAdjustedSupply = pool.adjustedSupply - user.adjustedAmount;
//     user.adjustedAmount = adjustedAmount;
//     pool.adjustedSupply = newAdjustedSupply + adjustedAmount;
//     user.rewardDebt = (adjustedAmount * _accRewardPerShare) / 1e12;
//   }

//   // Safe reward token transfer function, just in case if rounding error causes pool to not have enough
//   function _safeRewardTransfer(address _user, uint256 _rewardAmt) internal returns (uint256) {
//     uint256 rewardBal = rewardToken.balanceOf(address(this));
//     if (_rewardAmt > rewardBal) {
//       _rewardAmt = rewardBal;
//     }
//     if (_rewardAmt > 0) {
//       address receiver = claimReceiver[_user];
//       if (receiver == address(0)) {
//         receiver = _user;
//       }
//       rewardToken.transfer(receiver, _rewardAmt);
//       emit ClaimedReward(msg.sender, _user, receiver, _rewardAmt);
//     }
//     return _rewardAmt;
//   }

//   // NOTE: need review
//   function inCaseTokensGetStuck(address _token, uint256 _amount) public onlyOwner {
//     require(_token != address(rewardToken), "!safe");
//     IERC20(_token).safeTransfer(msg.sender, _amount);
//   }

//   /**
//     @notice Update a user's boost for one or more deposited tokens
//     @param _user Address of the user to update boosts for
//     @param _pids Array of LP tokens to update boost for
//   */
//   function updateUserBoosts(address _user, uint256[] calldata _pids) external {
//     for (uint256 i = 0; i < _pids.length; i++) {
//       uint256 pid = _pids[i];
//       uint256 accRewardPerShare = _updatePool(pid);
//       UserInfo storage user = userInfo[pid][_user];
//       if (user.adjustedAmount > 0) {
//         uint256 pending = (user.adjustedAmount * accRewardPerShare) / 1e12 - user.rewardDebt;
//         if (pending > 0) {
//           user.claimable += pending;
//         }
//       }
//       _updateLiquidityLimits(_user, pid, user.shares, accRewardPerShare);
//     }
//   }

//   // Withdraw without caring about rewards. EMERGENCY ONLY.
//   function emergencyWithdraw(uint256 _pid) public nonReentrant {
//     address _userAddress = msg.sender;
//     PoolInfo storage pool = poolInfo[_pid];
//     UserInfo storage user = userInfo[_pid][_userAddress];

//     uint256 wantLockedTotal = pool.strategy.wantLockedTotal();
//     uint256 sharesTotal = pool.strategy.sharesTotal();
//     uint256 amount = (user.shares * wantLockedTotal) / sharesTotal;

//     pool.strategy.withdraw(_userAddress, amount);

//     pool.token.safeTransfer(_userAddress, amount);
//     pool.adjustedSupply -= user.adjustedAmount;
//     emit EmergencyWithdraw(_userAddress, _pid, amount);
//     delete userInfo[_pid][_userAddress];
//   }
// }