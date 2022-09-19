// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFactory{
    function getPool(address _tokenAddress) external returns(address);
}

contract Pool is ERC20 {
    
    event Exchange(address indexed from, address fromTokenAddress, address indexed toTokenAddress, uint256 fromAmount ,uint256 toAmount);
    event Liquidity(address indexed from, uint256 liquidityAmount, uint256 ethAmount, uint256 tokenAmount, bool isAdd);

    address tokenAddress;
    address factoryAddress;

    address constant ethAddress = address(0xeeeeeeeeeeee);

    constructor(address _token) ERC20("Uniswap-LP","UL") {
        require(_token != address(0),"ADE");
        tokenAddress = _token;
        factoryAddress = msg.sender;
    }
    //获取这个兑换池中的token的余量
    //return 兑换池的token余额
    function getReserve() private view returns(uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    //增加流动性，因为会接受ETH，所以是payable
    //param: msg.value表示增加的ETH
    //        _tokenAmount表示增加的token的数量，在此之前，需要授权pool合约该token的权限。
    //return: liquidity:表示新增的流动性的数值
    function addLiquidity(uint256 _tokenAmount) public payable returns(uint256 liquidity) {
        require(_tokenAmount > 0 && msg.value > 0, "EAM");
        
        if(getReserve() == 0) { //这里表示是第一次初始化
            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), _tokenAmount);
            liquidity = address(this).balance;  //这里以ETH作为增加的流动性的指标
            _mint(msg.sender, liquidity);       //分发liquidity数量的流动性标记
            emit Liquidity(msg.sender,liquidity,msg.value,_tokenAmount,true);
            return liquidity;

        }else {

            uint256 ethReserve = address(this).balance - msg.value;
            uint256 tokenReserve = IERC20(tokenAddress).balanceOf(address(this));
            uint256 tokenAmount = (msg.value * tokenReserve) / ethReserve;  //计算实际需要的token
            require(_tokenAmount > tokenAmount,"EA");                       //提供的token不能小于实际需要的

            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), tokenAmount);     //扣减token
            liquidity = (msg.value * totalSupply())/ethReserve;             //通过提供的eth占比，分配流动性标记
            _mint(msg.sender, liquidity);                                   //分发liquidity数量流动性标记
            emit Liquidity(msg.sender,liquidity,msg.value,_tokenAmount,true);
            return liquidity;
        }
    }

    //移除流动性
    //param: _amount: 需要退出的流动性数量
    //return: ethAmount:退还的ETH数量 
    //      tokenAMount:退还的token的数量
    function removeLiquidity(uint256 _amount) public returns(uint256,uint256) {
        require(_amount>0,"_AE");
        require(balanceOf(msg.sender) >= _amount,"_AN");
        IERC20 token = IERC20(tokenAddress);
        uint256 ethAmount =  _amount * address(this).balance / totalSupply();       //按照比例退还ETH
        uint256 tokenAmount = _amount * token.balanceOf(address(this)) / totalSupply(); //按照比例退还token
        _burn(msg.sender, _amount);                                                 //销毁流动性标记
        payable(msg.sender).transfer(ethAmount);
        token.transfer(msg.sender, tokenAmount);
        emit Liquidity(msg.sender,_amount,ethAmount,tokenAmount,false);
        return (ethAmount, tokenAmount);
    }

    //计算交易获得的token/eth的数量，公式(x-a)(y+b)=x*y ，计算得到a=(xb)/(y+b)，这里还扣除了1%的手续费，留在pool中。
    function getAmount(uint256 inputAmount, uint256 inputReserve, uint256 outputReserve) private pure returns(uint256) {
        require(inputReserve > 0 && outputReserve > 0 , "IOE");
        uint256 amountAfterFee = inputAmount*99;
        return amountAfterFee*outputReserve/(inputReserve*100 + amountAfterFee);
    }

    //计算交易获得的token数量
    //param: _ethSold，消费的eth数量
    //return: 获得的token的数量
    function getTokenAmount(uint256 _ethSold) private view returns(uint256) {
        require(_ethSold > 0,"_EE");
        uint256 tokenReserve = getReserve();
        return getAmount(_ethSold, address(this).balance, tokenReserve);
    }

    //计算交易获得的ETH的数量
    //param: _tokenSold 消费的token的数量
    //return: 获得的ETH数量
    function getEthAmount(uint256 _tokenSold) private view returns(uint256) {
        require(_tokenSold > 0,"_TE");
        uint256 tokenReserve = getReserve();
        return getAmount(_tokenSold, tokenReserve, address(this).balance);
    }

    //ETH交换token的接口
    //param: _mineTokens: 根据前端展示的滑点，计算得到的获得的最小的token数量
    //return: 获得的token的数量
    function ethToTokenSwap(uint256 _minTokens) public payable returns(uint256) {
        require(msg.value > 0 && address(this).balance - msg.value > 0,"VE");
        uint256 tokenReserve = getReserve();
        //计算获得的token数量
        uint256 tokenBought = getAmount(msg.value, address(this).balance - msg.value, tokenReserve);
        //实际得到的要大于等于用户看到的最小能获得的
        require(tokenBought >= _minTokens,"NE");
        //发送token
        IERC20(tokenAddress).transfer(msg.sender,  tokenBought);
        emit Exchange(msg.sender, ethAddress, tokenAddress, msg.value, tokenBought);
        return tokenBought;
    }

    //token交换ETH的接口
    //param: _tokenSold:出售的token数量  _minEth:能获得的最小的eth数量
    //return: 实际获得的eth数量
    function tokenToEth(uint256 _tokenSold, uint256 _minEth) public returns(uint256) {
        require(_tokenSold > 0 && address(this).balance > 0,"PE");
        uint256 ethBought = getEthAmount(_tokenSold);
        //实际得到的要大于等于用户看到最小能获得的
        require(ethBought >= _minEth,"EN");
        //扣减token
        IERC20(tokenAddress).transferFrom(msg.sender, address(this), _tokenSold);
        //发送ETH
        payable(msg.sender).transfer(ethBought);
        emit Exchange(msg.sender, tokenAddress, ethAddress, _tokenSold, ethBought);
        return ethBought;
    }

    //token交换token接口
    //param: _tokenSold:出售的token数量 _minTokensBought:最小可以获得的token数量 _tokenAddress:目标token地址
    //return: 实际获得的token数量
    function tokenToTokenSwap(uint256 _tokenSold, uint256 _minTokensBought, address _tokenAddress) public returns(uint256) {
        address pool = IFactory(factoryAddress).getPool(_tokenAddress);
        //这里不能自己交易自己
        require(pool != address(this) && pool != address(0) , "TONEX");
        //池子要先初始化过
        require(address(this).balance > 0 && pool.balance > 0 ,"NI");

        uint256 tokenReserve = getReserve();
        //先计算出售获得的ETH数量
        uint256 ethBought = getAmount(_tokenSold, tokenReserve, address(this).balance);
        //扣减token
        IERC20(tokenAddress).transfer(address(this), _tokenSold);
        //调用ETH交易token的接口
        uint256 tokenAmount = Pool(pool).ethToTokenSwap{value: ethBought}(_minTokensBought);
        emit Exchange(msg.sender, tokenAddress, _tokenAddress, _tokenSold, tokenAmount);
        return tokenAmount;
    }
}