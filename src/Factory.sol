// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/proxy/Clones.sol";
import {Launchpad} from "./Launchpad.sol";
import {Token} from "./Token.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

contract Factory is OwnableUpgradeable, UUPSUpgradeable {
    using Clones for address;

    address[] public launchpad;
    address[] public token;
    address public campaignMasterContract;
    address public tokenMasterContract;
    address public signer;
    uint public fee;
    uint public fee_pool;
    uint public nonce;
    address public fee_token;

    event DeployCampaign(address, uint);
    event DeployToken(address, uint);
    event RedeemFee(address, uint);
    event SetFee(address, uint);
    error InvalidSignature();

    error TransferNativeFailed();
    error InvalidFee();

    function initialize(
        address _campaignMasterContract,
        address _tokenMasterContract,
        address _admin,
        address _signer
    ) public initializer {
        __Ownable_init(_admin);
        __UUPSUpgradeable_init();

        campaignMasterContract = _campaignMasterContract;
        tokenMasterContract = _tokenMasterContract;
        signer = _signer;
        nonce = 0;
        fee_pool = 0;
        fee = 0;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function createToken(
        string memory _name,
        string memory _symbol,
        uint _amount,
        uint _token_id,
        address _owner
    ) external payable returns (address) {
        Token tokenClone = Token(address(tokenMasterContract).clone());
        tokenClone.initialize(
            _name,
            _symbol,
            _amount,
            _owner
        );

        token.push(address(tokenClone));

        emit DeployToken(address(tokenClone), _token_id);
        return address(tokenClone);
    }

    function createCampaign(
        address _system_owner,
        Launchpad.Campaign memory _campaign,
        // address _campaign_owner,
        // address _base_token,
        // uint256 _time_start,
        // uint256 _time_end,
        // uint256 _time_start_phase_two,
        // uint256 _time_end_phase_two,
        // address _quote_token,
        // uint256 _rate,
        uint256 _camapaign_id,
        // bool _is_overflow,
        bytes memory _signature
    ) external payable {
        bytes32 message = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    signer,
                    nonce++,
                    _campaign.campaign_owner,
                    _campaign.base_token,
                    _campaign.time_start,
                    _campaign.time_end,
                    _campaign.quote_token,
                    _campaign.rate,
                    _campaign.is_overflow
                )
            )
        );
        if (
            !SignatureChecker.isValidSignatureNow(signer, message, _signature)
        ) {
            revert InvalidSignature();
        }

        Launchpad.VestingPeriod[] memory _vesting_periods = new Launchpad.VestingPeriod[](2);
        _vesting_periods[0] = Launchpad.VestingPeriod(0, 1);
        _vesting_periods[1] = Launchpad.VestingPeriod(2, 3);
        uint[] memory _vesting_percent = new uint[](2);
        _vesting_percent[0] = 10000;
        _vesting_percent[1] = 10000;

        Launchpad pool = Launchpad(address(campaignMasterContract).clone());
        pool.initialize(
            _system_owner,
            _campaign,
            _vesting_periods,
            _vesting_percent,
            address(this)
        );

        launchpad.push(address(pool));

        if (fee_token != address(0)) {
            TransferHelper.safeTransferFrom(
                fee_token,
                msg.sender,
                address(this),
                fee
            );
        } else {
            if (fee != msg.value) {
                revert InvalidFee();
            }
            fee_pool += msg.value;
        }

        emit DeployCampaign(address(pool), _camapaign_id);
    }

    function setCampaignMasterContract(address _campaignMasterContract) external onlyOwner {
        campaignMasterContract = _campaignMasterContract;
    }

    function setTokenMasterContract(address _tokenMasterContract) external onlyOwner {
        tokenMasterContract = _tokenMasterContract;
    }

    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
    }

    function setFee(
        uint _fee,
        address _fee_token,
        address _receiver
    ) external onlyOwner {
        fee = _fee;
        fee_token = _fee_token;

        if (fee_pool > 0) {
            redeemFee(_receiver);
        }

        emit SetFee(_fee_token, _fee);
    }

    function redeemFee(address _receiver) public onlyOwner {
        uint _tmp_fee = fee_pool;
        if (fee_token == address(0)) {
            (bool sent, bytes memory data) = _receiver.call{value: _tmp_fee}(
                ""
            );
            if (!sent) {
                revert TransferNativeFailed();
            }
        } else {
            TransferHelper.safeTransfer(fee_token, _receiver, _tmp_fee);
        }
        fee_pool = 0;

        emit RedeemFee(_receiver, _tmp_fee);
    }

    function getChildren() external view returns (address[] memory) {
        return launchpad;
    }
}
