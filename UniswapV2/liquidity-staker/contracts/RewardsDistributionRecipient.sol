pragma solidity ^0.5.16;

contract RewardsDistributionRecipient {
    address public rewardsDistribution;     //stacking合约的管理员地址，也就是Factory合约地址

    function notifyRewardAmount(uint256 reward) external;

    modifier onlyRewardsDistribution() {    //检查一定要是管理员地址的修饰器
        require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
        _;
    }
}