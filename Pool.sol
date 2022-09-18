// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFactory{
    function getPool(address _tokenAddress) external returns(address);
}

contract Pool is ERC20 {
    event Exchange(address indexed from, address fromTokenAddress, address indexed toTokenAddress, uint256 fromAmount ,uint256 toAmount);
    // constructor(string memory name, string memory symbol, uint256 initSupply) ERC20(name,symbol) {
    //     _mint(msg.sender, initSupply);
    // }

    address tokenAddress;
    address factoryAddress;
    constructor(address _token) ERC20("Uniswap-LP","UL") {
        require(_token != address(0),"ADE");
        tokenAddress = _token;
        factoryAddress = msg.sender;
    }

    function getReserve() private view returns(uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    // function

    function addLiquidity(uint256 _tokenAmount) public payable returns(uint256 liquidity) {
        require(_tokenAmount > 0, "EAM");
        
        if(getReserve() == 0) {
            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), _tokenAmount);
            liquidity = address(this).balance;
            _mint(msg.sender, liquidity);
            return liquidity;

        }else {

            uint256 ethReserve = address(this).balance;
            uint256 tokenReserve = IERC20(tokenAddress).balanceOf(address(this));
            uint256 tokenAmount = (msg.value * tokenReserve) / ethReserve;
            require(_tokenAmount > tokenAmount,"EA");

            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), tokenAmount);
            liquidity = (msg.value * totalSupply())/ethReserve;
            _mint(msg.sender, liquidity);
            return liquidity;
        }
    }

    function removeLiquidity(uint256 _amount) public returns(uint256,uint256) {
        require(_amount>0,"_AE");
        IERC20 token = IERC20(tokenAddress);
        uint256 ethAmount =  _amount * address(this).balance / totalSupply();
        uint256 tokenAmount = _amount * token.balanceOf(address(this)) / totalSupply();
        _burn(msg.sender, _amount);
        payable(msg.sender).transfer(ethAmount);
        token.transfer(msg.sender, tokenAmount);
        return (ethAmount, tokenAmount);
    }

    //收取手续费
    function getAmount(uint256 inputAmount, uint256 inputReserve, uint256 outputReserve) private pure returns(uint256) {
        require(inputReserve > 0 && outputReserve > 0 , "IOE");
        uint256 amountAfterFee = inputAmount*99;
        return amountAfterFee*outputReserve/(inputReserve*100 + amountAfterFee);
    }

    function getTokenAmount(uint256 _ethSold) private view returns(uint256) {
        require(_ethSold > 0,"_EE");
        uint256 tokenReserve = getReserve();
        return getAmount(_ethSold, address(this).balance, tokenReserve);
    }

    function getEthAmount(uint256 _tokenSold) private view returns(uint256) {
        require(_tokenSold > 0,"_TE");
        uint256 tokenReserve = getReserve();
        return getAmount(_tokenSold, tokenReserve, address(this).balance);
    }

    function ethToTokenSwap(uint256 _minTokens) public payable returns(uint256) {
        uint256 tokenReserve = getReserve();
        uint256 tokenBought = getAmount(msg.value, address(this).balance - msg.value, tokenReserve);
        require(tokenBought > _minTokens,"NE");
        IERC20(tokenAddress).transfer(msg.sender,  tokenBought);
        emit Exchange(msg.sender, address(0xeeeeeeee), tokenAddress, msg.value, tokenBought);
        return tokenBought;
    }

    function tokenToEth(uint256 _tokenSold, uint256 _minEth) public returns(uint256) {
        require(_tokenSold > 0,"_TE");
        uint256 ethBought = getEthAmount(_tokenSold);
        require(ethBought >= _minEth,"EN");
        IERC20(tokenAddress).transferFrom(msg.sender, address(this), _tokenSold);
        payable(msg.sender).transfer(ethBought);

        emit Exchange(msg.sender, tokenAddress, address(0xeeeeeeee), _tokenSold, ethBought);
        return ethBought;
    }

    function tokenToTokenSwap(uint256 _tokenSold, uint256 _minTokensBought, address _tokenAddress) public returns(uint256) {
        address pool = IFactory(factoryAddress).getPool(_tokenAddress);
        require(pool != address(this) && pool != address(0), "TONEX");
        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmount(_tokenSold, tokenReserve, address(this).balance);
        IERC20(tokenAddress).transfer(address(this), _tokenSold);
        uint256 tokenAmount = Pool(pool).ethToTokenSwap{value: ethBought}(_minTokensBought);
        emit Exchange(msg.sender, tokenAddress, _tokenAddress, _tokenSold, tokenAmount);
        return tokenAmount;
    }
}