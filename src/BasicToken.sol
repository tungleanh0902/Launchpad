// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BasicToken is ERC20 {
    constructor(
        string memory name, string memory symbol, uint amount
    ) ERC20(name, symbol) {
        _mint(msg.sender, amount * 10**decimals());
    }
}