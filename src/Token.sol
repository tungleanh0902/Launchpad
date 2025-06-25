// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Token is ERC20Upgradeable, OwnableUpgradeable {
    function initialize(
        string memory name, string memory symbol, uint amount, address _owner
    ) external initializer() {
        __Ownable_init(_owner);
        __ERC20_init(name, symbol);
        _mint(_owner, amount * 10**decimals());
    }
}