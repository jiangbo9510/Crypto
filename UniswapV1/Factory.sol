//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Pool.sol";

contract Factory {
    mapping(address => address) public tokenToExchange;
    function createPool(address _token) public returns(address){
        require(_token != address(0),"ADE");
        require(tokenToExchange[_token] == address(0),"EX");

        Pool pool = new Pool(_token);
        tokenToExchange[_token] = address(pool);
        return address(pool);
    }
    
    function getPool(address _token) public view returns(address){
        return tokenToExchange[_token];
    }
}