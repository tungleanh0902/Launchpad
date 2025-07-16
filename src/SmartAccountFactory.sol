// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/proxy/Clones.sol";
import {SmartAccount} from "./SmartAccount.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract SmartAccountFactory is OwnableUpgradeable, UUPSUpgradeable {
    using Clones for address;

    address[] public smartAccount;
    address public smartAccountContract;

    event CreateNewSmartAccount(address tx_payer, address smart_account, address user);

    function initialize(
        address _smartAccountContract,
        address _admin
    ) public initializer {
        __Ownable_init(_admin);
        __UUPSUpgradeable_init();

        smartAccountContract = _smartAccountContract;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function createSmartAccount(
        address _tx_payer,
        address _user,
        address _hot_wallet
    ) external payable returns (address payable) {
        SmartAccount smartAccountClone = SmartAccount(payable(address(smartAccountContract).clone()));
        smartAccountClone.initialize(
            _tx_payer,
            _user,
            _hot_wallet
        );

        smartAccount.push(address(smartAccountClone));

        emit CreateNewSmartAccount(_tx_payer, address(smartAccountClone), _user);
        return payable(address(smartAccountClone));
    }

    function setSmartAccountContract(address _smartAccountContract) external onlyOwner {
        smartAccountContract = _smartAccountContract;
    }
}
