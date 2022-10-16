pragma solidity >=0.4.24;


interface IStakingRewards {
    // Views
    // 查询接口
    function lastTimeRewardApplicable() external view returns (uint256);    //有奖励的最近区块数

    function rewardPerToken() external view returns (uint256);              //每单位token奖励的数量

    function earned(address account) external view returns (uint256);       //已经赚取但是没有提现的token

    function getRewardForDuration() external view returns (uint256);        //挖矿奖励总量

    function totalSupply() external view returns (uint256);                 //总质押量

    function balanceOf(address account) external view returns (uint256);    //用户的质押余额

    // Mutative
    // 涉及到数据修改的接口
    function stake(uint256 amount) external;    //质押

    function withdraw(uint256 amount) external; //提现，解除质押

    function getReward() external;              //提取奖励

    function exit() external;                   //退出
}