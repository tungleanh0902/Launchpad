// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SmartAccount is PausableUpgradeable {
    
    address public tx_payer;
    address public user;
    address public hot_wallet;

    uint public nonce;

    error InvalidSignature();
    error InvalidInput();

    function initialize(
        address _tx_payer,
        address _user,
        address _hot_wallet
    ) external initializer() {
        tx_payer = _tx_payer;
        user = _user;
        hot_wallet = _hot_wallet;

        nonce = 0;
    }

    function sweepToken(
        address[] memory _tokens,
        bytes memory _user_signature
    ) external {
        bytes32 message = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    user,
                    _tokens,
                    nonce++
                )
            )
        );
        if (
            !SignatureChecker.isValidSignatureNow(user, message, _user_signature)
        ) {
            revert InvalidSignature();
        }

        for (uint256 index = 0; index < _tokens.length; index++) {
            if (_tokens[index] == address(0)) {
                uint balance = address(this).balance;
                TransferHelper.safeTransferETH(hot_wallet, balance);
            } else {
                uint balance = ERC20(_tokens[index]).balanceOf(address(this));
                TransferHelper.safeTransfer(_tokens[index], hot_wallet, balance);
            }
        }
    }

    function withdrawToken(
        address _token,
        uint _amount,
        address _receiver,
        bytes memory _user_signature,
        bytes memory _tx_payer_signature
    ) external payable {
        uint current_nonce = nonce;
        bytes32 message_user = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    user,
                    _token,
                    current_nonce
                )
            )
        );

        bytes32 message_tx_payer = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    tx_payer,
                    _token,
                    current_nonce
                )
            )
        );

        current_nonce++;

        if (
            !SignatureChecker.isValidSignatureNow(user, message_user, _user_signature) ||
            !SignatureChecker.isValidSignatureNow(tx_payer, message_tx_payer, _tx_payer_signature)
        ) {
            revert InvalidSignature();
        }

        if (_token == address(0)) {
            TransferHelper.safeTransferETH(_receiver, _amount);
        } else {
            TransferHelper.safeTransferFrom(_token, hot_wallet, _receiver, _amount);
        }
    }

    // receive() external payable {}
}