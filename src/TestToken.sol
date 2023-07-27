// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract TestToken is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol, decimals) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
