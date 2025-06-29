// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console} from "forge-std/Script.sol";
import {Launchpad} from "../src/Launchpad.sol";
import { Factory } from '../src/Factory.sol';
import {Token} from "../src/Token.sol";
import {SmartAccountFactory} from "../src/SmartAccountFactory.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {BaseScript} from "./Base.s.sol";

contract CounterScript is BaseScript {
    Token public token;
    address signer = 0xfA893b687c0C28e6B08fB996C26bC6f5e268af0d;

    Factory factoryProxy;
    SmartAccount smartAccount;
    SmartAccountFactory smartAccountFactory;
    SmartAccountFactory smartAccountFactoryProxy;
    Factory public factory;
    Launchpad public launchpad;
    function run() public broadcast {
        // depoy_launchpad_impl();
        // deploy_token_impl();
        // deployToken();
        // deploy_factory();

        // deploy_smart_account_impl();
        // deploy_smart_account_factory();
    
        set_smart_account_impl();
    }

    function create_campaign() public {
        // address clonedCampaign = factoryProxy.createCampaign(signer, signer, 0x8C29102eDc3D2fF48f6dD48644D7858958233573, 1750425500, 2750425500, 0xF2cE390706Adc5C22a66570E744E5D4fE8FA88b4, 100000, 0, true);

        // Launchpad(clonedCampaign).campaign();
    }

    function depoy_launchpad_impl() public {
        launchpad = new Launchpad();
    }

    function deploy_token_impl() public {
        token = new Token();
    }

    function deploy_factory() public {
        Factory factory = new Factory();

        bytes memory hashRouter = abi.encodeWithSignature(
            "initialize(address,address,address,address)", 0x262844440d94794C5946DCaf2e637ba8b294AF3E, 0x02A84B8A8a885461f689ea520F81DeD056f3a418, signer, signer
        );

        factoryProxy = Factory(address(new ERC1967Proxy(address(factory), hashRouter)));
    }

    function deploy_smart_account_impl() public {
        smartAccount = new SmartAccount();
    }

    function deploy_smart_account_factory() public {
        SmartAccountFactory smartAccountFactory = new SmartAccountFactory();

        bytes memory hashRouter = abi.encodeWithSignature(
            "initialize(address,address)", address(0x5A6688E8eD1a15F34Fd847B8bFE66D6Ba0E40A09), signer
        );

        smartAccountFactoryProxy = SmartAccountFactory(address(new ERC1967Proxy(address(smartAccountFactory), hashRouter)));
    }

    function set_smart_account_impl() public {
        SmartAccountFactory smartAccountFactoryProxy = SmartAccountFactory(address(0x7586Bc78EBd19908fc83Fd794Fa9dF2A871F234c));
        smartAccountFactoryProxy.setSmartAccountContract(address(0xAa77DCe6d78FadE3dDc8d32A5caAce9edEE9D7D2));
    }

    function deployToken() public {
        // {
        //     // deploy token
        //     address token = address(new Token("HVT", "HVT"));
        // }

        // USDT: 0xF2cE390706Adc5C22a66570E744E5D4fE8FA88b4
        // HVT: 0x8C29102eDc3D2fF48f6dD48644D7858958233573
    }
}
// forge script ./script/Deploy.s.sol --slow --rpc-url https://eth-sepolia.public.blastapi.io --etherscan-api-key 4EWVY8CBI6YQCA5CDK9W5KVP3Q95IG2JVF --broadcast --verify -vvvv


// token impl contract: 0x02A84B8A8a885461f689ea520F81DeD056f3a418.
// launchpad impl contract: 0x262844440d94794C5946DCaf2e637ba8b294AF3E
// smart account impl contract: 0xAa77DCe6d78FadE3dDc8d32A5caAce9edEE9D7D2