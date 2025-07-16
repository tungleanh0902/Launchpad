// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test, console} from "forge-std/Test.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {SmartAccountFactory} from "../src/SmartAccountFactory.sol";

contract SmartAccountTest is Test {
    string public forkUrl = "https://eth-sepolia.public.blastapi.io";

    SmartAccount public smartAccount;

    address signer = 0xfA893b687c0C28e6B08fB996C26bC6f5e268af0d;

    SmartAccountFactory factoryProxy;

    address clonedSmartAccount;

    function setUp() public {
        vm.selectFork(vm.createFork(forkUrl));
        vm.startPrank(signer);

        smartAccount = new SmartAccount();

        test_deploy_factory();
        // test_clone_smartAccount(); // Remove this from setUp, let it be called separately
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
        // Use a test address that we control the private key for
        address testUser = vm.addr(0x49c1aff5472dd3a61b6710d42883750d0bcf2207b28191a480e82bc35e6bf701); // This creates address from private key 1
        
        address clonedSmartAccount = factoryProxy.createSmartAccount(
            0x310daE0406aB7d009061d67Dc03A28dA15136be1, 
            testUser,  // Use our test user
            0xfA893b687c0C28e6B08fB996C26bC6f5e268af0d
        );

        SmartAccount smartAccount = SmartAccount(payable(clonedSmartAccount));

        address[] memory tokens = new address[](1);
        tokens[0] = 0x8C29102eDc3D2fF48f6dD48644D7858958233573;

        address user = smartAccount.user();
        uint currentNonce = smartAccount.nonce();

        // Generate the exact same hash as the contract does
        bytes32 rawHash = keccak256(abi.encode(user, tokens, currentNonce));
        
        // Apply the same EthSignedMessageHash transformation that the contract will apply
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rawHash));
        
        // Sign the EthSignedMessageHash directly
        uint256 privateKey = 0x49c1aff5472dd3a61b6710d42883750d0bcf2207b28191a480e82bc35e6bf701;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedHash);
        
        bytes memory signature = abi.encodePacked(r, s, v);
        
        smartAccount.sweepToken(tokens, signature);
    }

    function test_withdraw_token() public {
        SmartAccount smartAccount = SmartAccount(payable(0x14e5A5D4Fd049F95EaD6b6f827fC6EB7Cf69638A));

        smartAccount.withdrawToken(
            0x8C29102eDc3D2fF48f6dD48644D7858958233573,
            10000,
            0x7B8B248B89Cd0F7CC24aebF9eE1A237E09C4557A,
            "0xfc7a63a18054dc0f46eba9349b02cef147c59ea74513f6af0959e4bfe8f5e71100941dd3dca1568412a11b93345aa1889e55cdf4d09820c5feaaf183402e1c301b",
            "0x52dc22e9954f309f98dd700f43d726a50b600eb7d5d1c2b87b0744775e66ce68745fc40e7dc11a45add9465750c6cf266c1b5b1e78980dc4a64714d1ba8cc7541b"
        );
    }

    function test_upgrade_factory() public {
        address preSigner = factoryProxy.smartAccountContract();

        SmartAccountFactory newImpl = new SmartAccountFactory();

        factoryProxy.upgradeToAndCall(address(newImpl), "");

        address postSigner = factoryProxy.smartAccountContract();

        assertEq(preSigner, postSigner);
    }
}
