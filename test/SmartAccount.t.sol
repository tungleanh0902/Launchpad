// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test, console} from "forge-std/Test.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {SmartAccountFactory} from "../src/SmartAccountFactory.sol";

contract SmartAccountTest is Test {
    // string public forkUrl = "https://eth-sepolia.public.blastapi.io";

    SmartAccount public smartAccount;

    address signer = 0xfA893b687c0C28e6B08fB996C26bC6f5e268af0d;

    SmartAccountFactory factoryProxy;

    address clonedSmartAccount;

    function setUp() public {
        // vm.selectFork(vm.createFork(forkUrl));
        vm.startPrank(signer);

        smartAccount = new SmartAccount();

        test_deploy_factory();
        test_clone_smartAccount();
    }

    function test_deploy_factory() public {
        SmartAccountFactory factory = new SmartAccountFactory();

        bytes memory hashFactory = abi.encodeWithSignature(
            "initialize(address,address)",
            address(smartAccount),
            signer
        );

        factoryProxy = SmartAccountFactory(
            address(new ERC1967Proxy(address(factory), hashFactory))
        );
    }

    function test_clone_smartAccount() public {
        clonedSmartAccount = factoryProxy.createSmartAccount(signer, signer, signer);
    }

    function test_upgrade_factory() public {
        address preSigner = factoryProxy.smartAccountContract();

        SmartAccountFactory newImpl = new SmartAccountFactory();

        factoryProxy.upgradeToAndCall(address(newImpl), "");

        address postSigner = factoryProxy.smartAccountContract();

        assertEq(preSigner, postSigner);
    }
}
