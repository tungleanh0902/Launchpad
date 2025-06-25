// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test, console} from "forge-std/Test.sol";
import { Launchpad } from '../src/Launchpad.sol';
import { Factory } from '../src/Factory.sol';
import { Token } from '../src/Token.sol';

contract LaunchpadTest is Test {
    Launchpad public launchpad;
    Token public token;

    address launchpadState;

    address signer = 0x310daE0406aB7d009061d67Dc03A28dA15136be1;

    Factory factoryProxy;

    address clonedCampaign;
    address clonedToken;

    Token tokenA;
    Token tokenB;

    function setUp() public {
        vm.startPrank(signer);
        // tokenA = new Token("a", "a");
        // tokenB = new Token("b", "b");

        launchpad = new Launchpad();

        token = new Token();

        test_deploy_factory();
        test_clone_token();
    }

    function test_deploy_factory() public {
        Factory factory = new Factory();

        bytes memory hashRouter = abi.encodeWithSignature(
            "initialize(address,address,address,address)", address(launchpad), address(token), signer, signer
        );

        factoryProxy = Factory(address(new ERC1967Proxy(address(factory), hashRouter)));
    }

    function clone_launchpad() public {
        // clonedCampaign = factoryProxy.createCampaign(signer, signer, address(tokenA), 1750425500, 2750425500, 2750425501, 2750425503, address(tokenB), 100000, 0, true);

        // Launchpad(clonedCampaign).campaign();
    }

    function test_clone_token() public {
        clonedToken = factoryProxy.createToken("a", "b", 10, 10, signer);

        Token(clonedToken).totalSupply();
    }

    // function test_depositFund_shoudlRight() public {
    //     address clonedCampaign1 = factoryProxy.createCampaign(signer, signer, address(tokenA), 1, 2750425500, address(tokenB), 100000, 1, true);
    //     Launchpad(clonedCampaign1).campaign();

    //     address clonedCampaign2 = factoryProxy.createCampaign(signer, signer, address(tokenA), 2, 2750425500, address(tokenB), 100000, 2, true);
    //     Launchpad(clonedCampaign2).campaign();

    //     address clonedCampaign3 = factoryProxy.createCampaign(signer, signer, address(tokenA), 3, 2750425500, address(tokenB), 100000, 3, true);
    //     Launchpad(clonedCampaign3).campaign();
    // }

    function test_upgrade_factory() public {
        address preSigner = factoryProxy.signer();

        Factory newImpl = new Factory();

        factoryProxy.upgradeToAndCall(address(newImpl), "");
       
        address postSigner = factoryProxy.signer();

        assertEq(preSigner, postSigner);
    }
}
