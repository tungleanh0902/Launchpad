// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SmartAccount is PausableUpgradeable {
    
    address public user;
    address public hot_wallet;
    address public operator;

    uint public nonce;

    error InvalidSignature();
    error InvalidInput();

    function initialize(
        address _operator,
        address _user,
        address _hot_wallet
    ) external initializer() {
        user = _user;
        hot_wallet = _hot_wallet;
        operator = _operator;
        nonce = 0;
    }

    function sweepToken(
        address[] memory _tokens,
        bytes memory _user_signature
    ) external {
        bytes32 message = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    user,
                    _tokens,
                    nonce++
                )
            )
        );
        
        // Use ECDSA.recover for signature verification
        address recoveredSigner = ECDSA.recover(message, _user_signature);
        
        if (recoveredSigner != user) {
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
        bytes memory _operator_signature
    ) external payable {
        uint current_nonce = nonce;
        bytes32 message_user = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    user,
                    _token,
                    current_nonce
                )
            )
        );

        bytes32 message_operator = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encode(
                    operator,
                    _token,
                    current_nonce
                )
            )
        );

        if (
            ECDSA.recover(message_user, _user_signature) != user ||
            ECDSA.recover(message_operator, _operator_signature) != operator
        ) {
            revert InvalidSignature();
        }

        current_nonce++;

        if (_token == address(0)) {
            TransferHelper.safeTransferETH(_receiver, _amount);
        } else {
            TransferHelper.safeTransferFrom(_token, hot_wallet, _receiver, _amount);
        }
    }

    receive() external payable {}
}