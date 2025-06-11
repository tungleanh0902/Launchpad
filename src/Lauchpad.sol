// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

contract Launchpad {
    enum Type {
        Overflow,
        Fixed
    }
    
    struct Campaign {
        address token;
        uint amount;
        uint deadline;
    }
}
