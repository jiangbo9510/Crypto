pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/math/Math.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";

// Inheritance
import "./interfaces/IStakingRewards.sol";
import "./RewardsDistributionRecipient.sol";

contract StakingRewards is IStakingRewards, RewardsDistributionRecipient, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IERC20 public rewardsToken;             //奖励代币
    IERC20 public stakingToken;             //质押的LPtoken地址
    uint256 public periodFinish = 0;        //质押挖矿的结束时间
    uint256 public rewardRate = 0;          //挖矿速率，每秒挖矿奖励的数量
    uint256 public rewardsDuration = 60 days;   //挖矿时长，默认60days
    uint256 public lastUpdateTime;          //最近一次更新时间
    uint256 public rewardPerTokenStored;    //每个单位token奖励的数量

    mapping(address => uint256) public userRewardPerTokenPaid;  //用户每单位token奖励的数量
    mapping(address => uint256) public rewards;                 //用户奖励的token数量

    uint256 private _totalSupply;                   //总质押量
    mapping(address => uint256) private _balances;  //用户的质押余额

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken
    ) public {
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;     //
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    //挖矿结束：返回结束时间。挖矿未结束：返回当前时间。
    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    //这个是计算当前时间的每个质押可以领取的累积奖励，(10**18)倍
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {    //没人质押，那就是理论值
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                //rewardPerTokenStored += ((当前时间-上次数据更新的时间)*奖励速率/总质押量)
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
            );
    }

    //计算用户获得的奖励的token（已领取+未领取）
    function earned(address account) public view returns (uint256) {
        //用户质押数量*(每个单位质押的奖励-上一次数据更新的时候，每个单位的质押奖励) + 还没领取的奖励 = 用户最新的可以领取的奖励
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stakeWithPermit(uint256 amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);

        // permit
        IUniswapV2ERC20(address(stakingToken)).permit(msg.sender, address(this), amount, deadline, v, r, s);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    //质押的接口
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);  //记录这个人的质押数量
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);   //转入LPtoken
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);  //减少质押的数量
        stakingToken.safeTransfer(msg.sender, amount);  //转回去LPtoken
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];   //质押奖励
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);  //转入奖励
            emit RewardPaid(msg.sender, reward);
        }
    }

    //完全退出，1、拿回LPtoken。2、拿回奖励
    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */
    //限制性函数，只能Factory合约调用
    function notifyRewardAmount(uint256 reward) external onlyRewardsDistribution updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {  //periodFinish==0 ，一般都是走到这个分支
            rewardRate = reward.div(rewardsDuration);   //奖励的数量/奖励的周期，就是奖励的速率
        } else {
            //一轮挖矿还没结束，就开始了新一轮挖矿，奖励的速率要叠加。
            uint256 remaining = periodFinish.sub(block.timestamp);
            //旧一轮的挖矿的剩余奖励 = 挖矿剩余时间*奖励速率
            uint256 leftover = remaining.mul(rewardRate);
            //新的奖励速率 = （本次奖励+剩余奖励）/一轮挖矿的时间
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // 确保提供的奖励数量小于这个合约的奖励token的余额
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        // 速率要保持在一个正确的范围，避免奖励速率太高导致溢出
        // Reward + leftover 必须要小于 2^256 / 10^18 来比main溢出.

        uint balance = rewardsToken.balanceOf(address(this));

        //余额除时间，表示理论的速率要大于实际的速率，避免rewardRate虚高
        require(rewardRate <= balance.div(rewardsDuration), "Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);    //更新挖矿结束时间
        emit RewardAdded(reward);
    }

    /* ========== MODIFIERS ========== */

    //修饰器，更新奖励金额
    //出现数据更新的时候计算一次，不管是不是自己的质押增加或者退出
    //https://mirror.xyz/daxiong.eth/8_SxRihSUZMz9TUeHPkJHL_m24CoyAbzMQj5x_L5p6g 计算公式参考
    //简而言之，当前的质押收益 = 当前质押量*(当前的每个质押的累计奖励 - 上次数据更新的时候的每个质押累计奖励)
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();        //计算当前这一分钟的单个质押累计可以领取的奖励
        lastUpdateTime = lastTimeRewardApplicable();    //更新一次时间
        if (account != address(0)) {
            rewards[account] = earned(account); //刷新可以领取到奖励
            userRewardPerTokenPaid[account] = rewardPerTokenStored; //记录下来，下次计算的时候可以用上
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}

interface IUniswapV2ERC20 {
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}
