// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Factory } from "./Factory.sol";

contract Launchpad is PausableUpgradeable, ReentrancyGuard, OwnableUpgradeable {
    error InvalidCampaignOwner();
    error CampaignNotAvailable();
    error CampaignNotEnd();
    error CampaignPhaseTwoNotEnd();
    error InvalidSignature();
    error InvalidAmountToBuy();
    error InvalidTimestamp();
    error PhaseTwoNotStart();
    error PhaseTwoEnd();
    error OutOfBaseToken();
    error InvalidVestingPeriod();
    error PoolAlreadyStarted();
    error AlreadyClaimThisPeriod();
    error PoolNotReady();
    error VestingPeriodNotEnd();

    event CreateCampaign(address, address);
    event Join(address sender, address token, uint amount);
    event Deposit(address sender, address token, uint amount);
    event Claim(address sender, address token, uint amount, uint period_index);
    event Fund(address sender, address token, uint amount);
    event Withdraw(address sender, address token, uint amount);
    event Redeem(address sender, address quote_token, uint quote_amount);
    event BuyPhaseTwo(address sender, address quote_token, uint quote_amount);

    struct VestingPeriod {
        uint start;
        uint end;
    }

    struct Campaign {
        address campaign_owner;
        address base_token;
        uint time_start;
        uint time_end;
        uint time_start_phase_two;
        uint time_end_phase_two;
        address quote_token;
        uint rate; // base = rate.quote when rate is 10000/10000 = 100% with the same decimal
        bool is_overflow;
    }

    VestingPeriod[] public vesting_periods;
    uint[] public vesting_percent; // 10000/10000 = 100%

    uint private decimal_base_token;
    uint private decimal_quote_token;
    uint public base_pool; // base token
    uint public quote_pool; // quote token

    Campaign public campaign;
    uint public nonce;
    address[] private participant;
    Factory private factory;
    uint public fee_rate; // 10000/10000 = 100%
    address public treasury;

    mapping(address => uint) public positionByUser;
    mapping(address => uint) public claimedByUser;
    mapping(address => uint) public claimablePhaseTwoByUser;
    mapping(address => bool) public userRefunded;

    function initialize(
        address _owner,
        Campaign memory _campaign,
        VestingPeriod[] memory _vesting_periods,
        uint[] memory _vesting_percent,
        address _factory_contract
    ) external initializer() {
        __Ownable_init(_owner);
        campaign.campaign_owner = _campaign.campaign_owner;
        campaign.base_token = _campaign.base_token;
        campaign.quote_token = _campaign.quote_token;
        campaign.time_start = _campaign.time_start;
        campaign.time_end = _campaign.time_end;
        campaign.rate = _campaign.rate;
        campaign.is_overflow = _campaign.is_overflow;

        treasury = _owner;

        if (_vesting_periods.length != _vesting_percent.length) {
            revert InvalidVestingPeriod();
        }

        for (uint256 index = 0; index < _vesting_periods.length - 1; index++) {
            if (_vesting_periods[index].end <= _vesting_periods[index].start) {
                revert InvalidVestingPeriod();
            }
            if (_vesting_periods[index].end > _vesting_periods[index+1].start) {
                revert InvalidVestingPeriod();
            }
            vesting_periods.push(_vesting_periods[index]);
        }

        uint total_percent = 0;
        for (uint256 index = 0; index < _vesting_percent.length; index++) {
            total_percent += _vesting_percent[index];
            vesting_percent.push(_vesting_percent[index]);
        }

        if (total_percent != 10000) {
            revert InvalidVestingPeriod();
        }

        base_pool = 0;
        quote_pool = 0;
        nonce = 0;

        fee_rate = 200; // 2%

        if (_campaign.time_end_phase_two < _campaign.time_start_phase_two) {
            revert InvalidTimestamp();
        }
        if (_campaign.time_start_phase_two < _campaign.time_end) {
            revert InvalidTimestamp();
        }
        if (_campaign.time_end < _campaign.time_start) {
            revert InvalidTimestamp();
        }

        campaign.time_start_phase_two = _campaign.time_start_phase_two;
        campaign.time_end_phase_two = _campaign.time_end_phase_two;
        decimal_base_token = ERC20(_campaign.base_token).decimals();
        decimal_quote_token = ERC20(_campaign.quote_token).decimals();

        factory = Factory(_factory_contract);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    EXTERNAL
    //////////////////////////////////////////////////////////////////////////*/

    // For campaign owner
    function fundCampaign(uint _amount) external whenNotPaused() {
        Campaign memory _campaign = campaign;
        if (msg.sender != _campaign.campaign_owner) {
            revert InvalidCampaignOwner();
        }

        base_pool += _amount;
        TransferHelper.safeTransferFrom(_campaign.base_token, msg.sender, address(this), _amount);

        emit Fund(msg.sender, _campaign.base_token, _amount);
    }

    // For user
    function depositCampaign(uint amount, bytes memory signature, uint amount_allowed_to_buy_base_token) external nonReentrant() whenNotPaused() {
        Campaign memory _campaign = campaign;
        uint depositedAmount = positionByUser[msg.sender];
        
        if (base_pool == 0) {
            revert PoolNotReady();
        }
        
        if (block.timestamp < _campaign.time_start || block.timestamp > _campaign.time_end) {
            revert CampaignNotAvailable();
        }
        
        if (_campaign.is_overflow == false && signature.length == 0) {
            revert InvalidSignature();
        } else if (_campaign.is_overflow == false && signature.length > 0 ) {
            address signer = factory.signer();
            bytes32 message = MessageHashUtils.toEthSignedMessageHash(keccak256(abi.encodePacked(signer, nonce++, amount_allowed_to_buy_base_token)));
            if (!SignatureChecker.isValidSignatureNow(signer, message, signature)) {
                revert InvalidSignature();
            }

            uint max_quote_token_to_deposit = amount_allowed_to_buy_base_token * 10000 / campaign.rate;
            
            if (convertDecimal(max_quote_token_to_deposit, decimal_base_token, 18) < convertDecimal(amount + depositedAmount, decimal_quote_token, 18)) {
                revert InvalidAmountToBuy();
            }
        }
        bool joined = false;
        for (uint256 index = 0; index < participant.length; index++) {
            if (participant[index] == msg.sender) {
                joined = true;
                break;
            }
        }
        if (!joined) {
            participant.push(msg.sender);
        }

        quote_pool += amount;
        positionByUser[msg.sender] += amount;
        TransferHelper.safeTransferFrom(_campaign.quote_token, msg.sender, address(this), amount);

        emit Join(msg.sender, _campaign.quote_token, amount);
    }

    function buyPhaseTwo(uint _quote_amount) external nonReentrant() {
        Campaign memory _campaign = campaign;
        
        if (block.timestamp < _campaign.time_start_phase_two) {
            revert PhaseTwoNotStart();
        }
        if (block.timestamp > _campaign.time_end_phase_two) {
            revert PhaseTwoEnd();
        }
        (uint amount_base_token_to_be_claimed, ) = calculateBaseToken(_campaign);
        if (base_pool <= amount_base_token_to_be_claimed) {
            revert OutOfBaseToken();
        }

        uint amount_out = getAmountOut(_quote_amount);

        quote_pool += _quote_amount;

        TransferHelper.safeTransferFrom(_campaign.quote_token, msg.sender, address(this), _quote_amount);
        claimablePhaseTwoByUser[msg.sender] += amount_out;

        emit BuyPhaseTwo(msg.sender, _campaign.quote_token, _quote_amount);
    }

    // For user
    function claim() external nonReentrant() {
        Campaign memory _campaign = campaign;
        uint _decimal_quote_token = decimal_quote_token;
        uint _decimal_base_token = decimal_base_token;
        VestingPeriod[] memory _vesting_periods = vesting_periods;
        uint deposited_amount = positionByUser[msg.sender];

        if (block.timestamp < _vesting_periods[0].start) {
            revert CampaignNotAvailable();
        }
        
        uint period_index = 0;
        uint current_percent = 0;
        for (uint256 index = 0; index < _vesting_periods.length; index++) {
            if (block.timestamp < _vesting_periods[index].start) {
                break;
            }
            period_index = index;
            current_percent += vesting_percent[index];
        }

        uint total_to_claim;
        if (_campaign.is_overflow == false) {
            uint amount_base_token = _campaign.rate * positionByUser[msg.sender] / 10000;
            amount_base_token = convertDecimal(amount_base_token, _decimal_quote_token, _decimal_base_token);
            total_to_claim = amount_base_token;
        } else {
            uint max_amount_of_base_token = base_pool * deposited_amount / quote_pool;
            uint max_amount_of_quote_token = max_amount_of_base_token * 10000 / _campaign.rate;
            max_amount_of_quote_token = convertDecimal(max_amount_of_quote_token, _decimal_base_token, _decimal_quote_token);

            if (deposited_amount > max_amount_of_quote_token) {
                total_to_claim = max_amount_of_base_token;
                if (userRefunded[msg.sender] == false) {
                    userRefunded[msg.sender] = true;
                    TransferHelper.safeTransfer(_campaign.quote_token, msg.sender, deposited_amount - max_amount_of_quote_token);
                }
            }
            if (deposited_amount < max_amount_of_quote_token) {
                total_to_claim = deposited_amount * _campaign.rate / 10000;
                total_to_claim = convertDecimal(total_to_claim, _decimal_quote_token, _decimal_base_token);
            }
        }

        total_to_claim += claimablePhaseTwoByUser[msg.sender];
        uint amount_to_claim = total_to_claim * current_percent / 10000;
        uint claimed = claimedByUser[msg.sender];

        if (amount_to_claim == claimed) {
            revert AlreadyClaimThisPeriod();
        }

        claimedByUser[msg.sender] = amount_to_claim;
        TransferHelper.safeTransfer(_campaign.base_token, msg.sender, amount_to_claim - claimed);

        emit Claim(msg.sender, _campaign.base_token, amount_to_claim - claimed, period_index);
    }

    // For campaign owner
    function redeem() external nonReentrant() {
        Campaign memory _campaign = campaign;

        if (msg.sender != _campaign.campaign_owner) {
            revert InvalidCampaignOwner();
        }

        if (block.timestamp < _campaign.time_end_phase_two) {
            revert CampaignPhaseTwoNotEnd();
        }

        (uint amount_base_token_to_be_claimed, uint amount_quote_token_to_be_refund) = calculateBaseToken(_campaign);

        uint amount_redeem = quote_pool - amount_quote_token_to_be_refund;

        uint fee = amount_redeem * fee_rate / 10000;
        uint amount_redeem_with_fee = amount_redeem - fee;

        TransferHelper.safeTransfer(_campaign.quote_token, msg.sender, amount_redeem_with_fee);
        TransferHelper.safeTransfer(_campaign.quote_token, _campaign.quote_token, fee);

        emit Redeem(msg.sender, _campaign.quote_token, amount_redeem_with_fee);
    }

    function sweepRemainingToken() external nonReentrant() {
        Campaign memory _campaign = campaign;

        if (msg.sender != _campaign.campaign_owner) {
            revert InvalidCampaignOwner();
        }

        if (block.timestamp < vesting_periods[vesting_periods.length - 1].end) {
            revert VestingPeriodNotEnd();
        }

        uint remaining_base_token = ERC20(_campaign.base_token).balanceOf(address(this));
        uint remaining_quote_token = ERC20(_campaign.quote_token).balanceOf(address(this));

        TransferHelper.safeTransfer(_campaign.base_token, msg.sender, remaining_base_token);
        TransferHelper.safeTransfer(_campaign.quote_token, msg.sender, remaining_quote_token);
    }

    function getAmountOut(uint _quote_amount) view public returns (uint) {
        Campaign memory _campaign = campaign;
        uint _base_amount = _quote_amount * _campaign.rate / 10000;
        _base_amount = convertDecimal(_base_amount, decimal_quote_token, decimal_base_token);
        return _base_amount;
    }

    function setTreasury(address _treasury) external onlyOwner() {
        treasury = _treasury;
    }

    function setFeeRate(uint _fee_rate) external onlyOwner() {
        fee_rate = _fee_rate;
    }

    function setVestingPeriod(VestingPeriod[] memory _vesting_periods, uint[] memory _vesting_percent) external onlyOwner() {
        if (block.timestamp >= campaign.time_start) {
            revert PoolAlreadyStarted();
        }

        delete vesting_periods;
        delete vesting_percent;

        for (uint256 index = 0; index < _vesting_periods.length - 1; index++) {
            if (_vesting_periods[index].end <= _vesting_periods[index].start) {
                revert InvalidVestingPeriod();
            }
            if (_vesting_periods[index].end > _vesting_periods[index+1].start) {
                revert InvalidVestingPeriod();
            }
            vesting_periods.push(_vesting_periods[index]);
        }

        uint total_percent = 0;
        for (uint256 index = 0; index < _vesting_percent.length; index++) {
            total_percent += _vesting_percent[index];
            vesting_percent.push(_vesting_percent[index]);
        }

        if (total_percent != 10000) {
            revert InvalidVestingPeriod();
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPER
    //////////////////////////////////////////////////////////////////////////*/
    function calculateBaseToken(Campaign memory _campaign) private view returns (uint, uint) {
        uint _decimal_quote_token = decimal_quote_token;
        uint _decimal_base_token = decimal_base_token;

        uint amount_base_token_to_be_claimed;
        uint amount_quote_token_to_be_refund;

        for (uint256 index = 0; index < participant.length; index++) {
            if (_campaign.is_overflow) {
                uint position = positionByUser[participant[index]];
                uint max_amount_of_base_token = base_pool * position / quote_pool;
                uint max_amount_of_quote_token = max_amount_of_base_token * 10000 / _campaign.rate;
                max_amount_of_quote_token = convertDecimal(max_amount_of_quote_token, _decimal_base_token, _decimal_quote_token);
                uint amount_to_claim;
                if (position > max_amount_of_quote_token) {
                    amount_to_claim = max_amount_of_base_token;
                    amount_quote_token_to_be_refund += position - max_amount_of_quote_token;
                }
                if (position <= max_amount_of_quote_token) {
                    amount_to_claim = position * _campaign.rate / 10000;
                    amount_to_claim = convertDecimal(amount_to_claim, _decimal_quote_token, _decimal_base_token);
                }
                amount_base_token_to_be_claimed += amount_to_claim;
            } else {
                uint position = positionByUser[participant[index]];
                amount_base_token_to_be_claimed += convertDecimal(position * _campaign.rate / 10000, _decimal_quote_token, _decimal_base_token);
            }
        }
        
        return (amount_base_token_to_be_claimed, amount_quote_token_to_be_refund);
    }

    function convertDecimal(uint amount_to_convert, uint token_decimal_old, uint token_decimal_new) private view returns (uint) {
        if (token_decimal_old > token_decimal_new) {
            amount_to_convert = amount_to_convert / 10**(token_decimal_old-token_decimal_new);
        }
        if (token_decimal_old < token_decimal_new) {
            amount_to_convert = amount_to_convert * 10**(token_decimal_new-token_decimal_old);
        }
        return amount_to_convert;
    }
}
