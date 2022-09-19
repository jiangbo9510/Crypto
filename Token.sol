// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Token is ERC20{
    constructor(string memory name, string memory symbol) ERC20(name,symbol){
    }

    function create(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}