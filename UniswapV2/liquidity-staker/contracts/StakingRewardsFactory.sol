pragma solidity ^0.5.16;

import 'openzeppelin-solidity-2.3.0/contracts/token/ERC20/IERC20.sol';
import 'openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol';

import './StakingRewards.sol';

//工厂合约，主要用于部署StackingRewarding合约
contract StakingRewardsFactory is Ownable {
    // immutables
    address public rewardsToken;            //用于奖励的代币，其实就是UNI币
    uint public stakingRewardsGenesis;      //挖矿开始的时间

    // the staking tokens for which the rewards contract has been deployed
    address[] public stakingTokens;         //各个交易对pair合约中，提供流动性获得的LPtoken地址列表

    // info about rewards for a particular staking token
    //特定质押LPtoken的奖励信息
    struct StakingRewardsInfo {
        address stakingRewards;     //Stacking合约地址
        uint rewardAmount;          //质押合约每个周期的奖励的UNI的总的数量
    }

    // rewards info by staking token
    mapping(address => StakingRewardsInfo) public stakingRewardsInfoByStakingToken; //LPtoken to 质押合约信息

    constructor(
        address _rewardsToken,
        uint _stakingRewardsGenesis
    ) Ownable() public {
        //开始质押的时间不能大于等于当前时间
        require(_stakingRewardsGenesis >= block.timestamp, 'StakingRewardsFactory::constructor: genesis too soon');

        rewardsToken = _rewardsToken;
        stakingRewardsGenesis = _stakingRewardsGenesis;
    }

    ///// permissioned functions

    // deploy a staking reward contract for the staking token, and store the reward amount
    // the reward will be distributed to the staking reward contract no sooner than the genesis
    //部署stacking合约，设置奖励的数量
    //奖励分发给stacking合约不早于开始挖矿的时间
    // stakingToken LPtoken的地址
    function deploy(address stakingToken, uint rewardAmount) public onlyOwner {
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[stakingToken];
        require(info.stakingRewards == address(0), 'StakingRewardsFactory::deploy: already deployed');
        //创建stacking合约
        info.stakingRewards = address(new StakingRewards(/*_rewardsDistribution=*/ address(this), rewardsToken, stakingToken));
        info.rewardAmount = rewardAmount;
        stakingTokens.push(stakingToken);
    }

    ///// permissionless functions

    // call notifyRewardAmount for all staking tokens.
    //给所有有stacking合约的交易对，调用其notifyRewardAmount函数
    function notifyRewardAmounts() public {
        require(stakingTokens.length > 0, 'StakingRewardsFactory::notifyRewardAmounts: called before any deploys');
        for (uint i = 0; i < stakingTokens.length; i++) {
            notifyRewardAmount(stakingTokens[i]);
        }
    }

    // notify reward amount for an individual staking token.
    // this is a fallback in case the notifyRewardAmounts costs too much gas to call for all contracts
    // 分发UNI给各个stacking合约
    // 避免批量处理的notifyRewardAmounts合约可能出现gas不足，故该合约是fallback的，转账默认调用这个函数
    function notifyRewardAmount(address stakingToken) public {
        //一定要在开始质押之后
        require(block.timestamp >= stakingRewardsGenesis, 'StakingRewardsFactory::notifyRewardAmount: not ready');

        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[stakingToken];
        require(info.stakingRewards != address(0), 'StakingRewardsFactory::notifyRewardAmount: not deployed');

        if (info.rewardAmount > 0) {
            uint rewardAmount = info.rewardAmount;
            info.rewardAmount = 0;

            require(
                //从Factory合约转UNI币到stacking合约，这里需要先转UNI到Factory合约
                IERC20(rewardsToken).transfer(info.stakingRewards, rewardAmount),
                'StakingRewardsFactory::notifyRewardAmount: transfer failed'
            );
            //
            StakingRewards(info.stakingRewards).notifyRewardAmount(rewardAmount);
        }
    }
}