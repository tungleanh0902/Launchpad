// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Launchpad is UUPSUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    /*//////////////////////////////////////////////////////////////////////////
                                    ERROR
    //////////////////////////////////////////////////////////////////////////*/

    error InvalidCampaignOwner();
    error InvalidAmount();
    error CampaignNotAvailable();
    error CampaignNotEnd();
    error InvalidSignature();
    error InvalidAmountToBuy();
    error InsufficientPool();

    /*//////////////////////////////////////////////////////////////////////////
                                    STATE
    //////////////////////////////////////////////////////////////////////////*/

    
    enum Type {
        Overflow,
        Fixed
    }
    
    struct Campaign {
        address campaign_owner;
        address token_to_sell; // token that owner of campaign sell
        uint amount; // amount of token the owner want to sell
        uint time_start;
        uint time_end;
        address token_to_buy; // token that owner of campaign want to get
        uint rate; // a = rate.b when rate is 10000/10000 = 100% with the same decimal
        uint pool; // amount of token currently deposited into the campaign
        Type lauchtype;
        address[] whitelists;
    }

    uint id;
    uint nonce;
    address signer;

    mapping(uint => Campaign) public campaignById;
    // user per campaign to amount
    mapping (address => mapping (uint => uint)) positionByUser;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    INITIALIZER
    //////////////////////////////////////////////////////////////////////////*/

    function initialize(
        address _signer
    ) public initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);

        id = 0;
        nonce = 0;
        signer = _signer;
    }

    /**
     * @dev Authorizes an implementation upgrade.
     * Override required by {UUPSUpgradeable}. Restricts upgrades to the contract owner.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    /*//////////////////////////////////////////////////////////////////////////
                                    EXTERNAL
    //////////////////////////////////////////////////////////////////////////*/

    function createCampaign(Campaign memory _campaignParam) external onlyOwner() {
        uint currentId = id;
        campaignById[id] = _campaignParam;
        id = currentId + 1;
    }

    function depositFundCampaign(uint campaignId, uint amount) external{
        Campaign memory campaign = campaignById[campaignId];
        if (msg.sender != campaign.campaign_owner) {
            revert InvalidCampaignOwner();
        }

        campaignById[campaignId].amount += amount;
        TransferHelper.safeTransferFrom(campaign.token_to_sell, msg.sender, address(this), amount);
    }

    function withdrawFundCampaign(uint campaignId, uint amount) external {
        Campaign memory campaign = campaignById[campaignId];
        if (msg.sender != campaign.campaign_owner) {
            revert InvalidCampaignOwner();
        }

        if (amount > campaign.amount) {
            revert InvalidAmount();
        }

        TransferHelper.safeTransfer(campaign.token_to_sell, msg.sender, amount);
    }

    function joinCampaign(uint campaignId, uint amount, bytes memory signature, uint amount_allowed_to_buy) external nonReentrant() {
        Campaign memory campaign = campaignById[campaignId];
        uint depositedAmount = positionByUser[msg.sender][campaignId];
        if (block.timestamp < campaign.time_start || block.timestamp > campaign.time_end) {
            revert CampaignNotAvailable();
        }
        if (campaign.lauchtype == Type.Fixed && signature.length == 0) {
            revert InvalidSignature();
        } else {
            bytes32 message = MessageHashUtils.toEthSignedMessageHash(keccak256(abi.encodePacked(signer, nonce++, amount_allowed_to_buy)));
            if (!SignatureChecker.isValidSignatureNow(signer, message, signature)) {
                revert InvalidSignature();
            }
            uint amount_to_deposit_calculated_in_decimal_of_new_token = amount_allowed_to_buy * 10000 / campaign.rate;
            amount_to_deposit_calculated_in_decimal_of_new_token = convertDecimal(amount_to_deposit_calculated_in_decimal_of_new_token, campaign);
            uint amount_deposit_in_new_decimal = amount + depositedAmount;
            // uint decimal_token_to_buy = ERC20(campaign.token_to_buy).decimals();
            // uint decimal_token_to_sell = ERC20(campaign.token_to_sell).decimals();
            // if (decimal_token_to_buy < decimal_token_to_sell) {
            //     amount_to_deposit_calculated_in_decimal_of_new_token = amount_to_deposit_calculated_in_decimal_of_new_token * 10**(decimal_token_to_sell-decimal_token_to_buy);
            // } 
            // if (decimal_token_to_buy > decimal_token_to_sell) {
            //     amount_to_deposit_calculated_in_decimal_of_new_token = amount_to_deposit_calculated_in_decimal_of_new_token / 10**(decimal_token_to_buy-decimal_token_to_sell);
            // }
            if (amount_deposit_in_new_decimal > amount_to_deposit_calculated_in_decimal_of_new_token) {
                revert InvalidAmountToBuy();
            }
        }

        bool is_whitelisted = false;
        if (campaign.whitelists.length > 0) {
            for (uint256 index = 0; index < campaign.whitelists.length; index++) {
                if (campaign.whitelists[index] == msg.sender) {
                    is_whitelisted = true;
                    break;
                }
            }
            if (!is_whitelisted) {
                revert CampaignNotAvailable();
            }
        }
        campaignById[campaignId].pool += amount;
        positionByUser[msg.sender][campaignId] += amount;
        TransferHelper.safeTransferFrom(campaign.token_to_buy, msg.sender, address(this), amount);
    }

    function claim(uint campaignId) external nonReentrant() {
        Campaign memory campaign = campaignById[campaignId];
        uint deposited_amount = positionByUser[msg.sender][campaignId];
        if (block.timestamp < campaign.time_end) {
            revert CampaignNotEnd();
        }
        if (campaign.lauchtype == Type.Fixed) {
            uint amount_to_claim_in_token_to_buy_decimal = campaign.rate * positionByUser[msg.sender][campaignId] / 10000;
            amount_to_claim_in_token_to_buy_decimal = convertDecimal(amount_to_claim_in_token_to_buy_decimal, campaign);
            // uint decimal_token_to_buy = ERC20(campaign.token_to_buy).decimals();
            // uint decimal_token_to_sell = ERC20(campaign.token_to_sell).decimals();
            // if (decimal_token_to_buy < decimal_token_to_sell) {
            //     amount_to_claim_in_token_to_buy_decimal = amount_to_claim_in_token_to_buy_decimal * 10**(decimal_token_to_sell-decimal_token_to_buy);
            // } 
            // if (decimal_token_to_buy > decimal_token_to_sell) {
            //     amount_to_claim_in_token_to_buy_decimal = amount_to_claim_in_token_to_buy_decimal / 10**(decimal_token_to_buy-decimal_token_to_sell);
            // }
            // if (campaign.amount < amount_to_claim_in_token_to_buy_decimal) {
            //     revert InsufficientPool();
            // }
            campaignById[campaignId].amount -= amount_to_claim_in_token_to_buy_decimal;
            TransferHelper.safeTransfer(campaign.token_to_buy, msg.sender, amount_to_claim_in_token_to_buy_decimal);
        } else {
            uint amount_of_token_to_sell = campaign.amount * deposited_amount / campaign.pool;
            uint amount_of_token_to_buy_in_token_to_sell_decimal = amount_of_token_to_sell * 10000 / campaign.rate;
            amount_of_token_to_buy_in_token_to_sell_decimal = convertDecimal(amount_of_token_to_buy_in_token_to_sell_decimal, campaign);
            // uint decimal_token_to_buy = ERC20(campaign.token_to_buy).decimals();
            // uint decimal_token_to_sell = ERC20(campaign.token_to_sell).decimals();
            // if (decimal_token_to_sell < decimal_token_to_buy) {
            //     amount_of_token_to_buy_in_token_to_sell_decimal = amount_of_token_to_buy_in_token_to_sell_decimal * 10**(decimal_token_to_buy-decimal_token_to_sell);
            // } 
            // if (decimal_token_to_sell > decimal_token_to_buy) {
            //     amount_of_token_to_buy_in_token_to_sell_decimal = amount_of_token_to_buy_in_token_to_sell_decimal / 10**(decimal_token_to_sell-decimal_token_to_buy);
            // }
            // ???
            // TransferHelper.safeTransfer(campaign.token_to_buy, msg.sender, amount_of_token_to_buy_in_token_to_sell_decimal);
            // TransferHelper.safeTransfer(campaign.token_to_sell, msg.sender, amount_of_token_to_buy_in_token_to_sell_decimal);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPER
    //////////////////////////////////////////////////////////////////////////*/
    function convertDecimal(uint amount, Campaign memory campaign) returns (uint) {
        uint decimal_token_to_buy = ERC20(campaign.token_to_buy).decimals();
        uint decimal_token_to_sell = ERC20(campaign.token_to_sell).decimals();
        if (decimal_token_to_sell < decimal_token_to_buy) {
            amount = amount * 10**(decimal_token_to_buy-decimal_token_to_sell);
        } 
        if (decimal_token_to_sell > decimal_token_to_buy) {
            amount = amount / 10**(decimal_token_to_sell-decimal_token_to_buy);
        }
        return amount;
    }
}
