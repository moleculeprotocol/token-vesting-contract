// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Token } from "../contracts/test/Token.sol";
import { TokenVestingMerkle } from "../contracts/TokenVestingMerkle.sol";

contract TokenVestingMerkleTest is Test {
    Token internal token;
    TokenVestingMerkle internal tokenVesting;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address deployer = makeAddr("bighead");

    bytes32[] aliceProof = new bytes32[](2);

    function setUp() public {
        // Merkle Proof for alice
        aliceProof[0] = 0xc5fbf303e065e46aac5d88bccc69a3205806a5a48630b42adb7bac8d1df19054;
        aliceProof[1] = 0xd2f0a6e784ed3593172a638a403c0fc153417f85c3cbe10bf32c267e32d94885;

        vm.startPrank(deployer);
        token = new Token("Test Token", "TT", 18, 1000000 ether);

        // Iniate TokenVestingMerkle with the merkle root from the example MerkleTree `samples/merkleTree.json`
        tokenVesting =
        new TokenVestingMerkle(IERC20Metadata(token), "Virtual Test Token", "vTT", 0x8467a730f851f6c56a81c7e4100d38c2c5ae1ce0362e89428bbd51f97eff9635);

        token.transfer(address(tokenVesting), 1000000 ether);
        vm.stopPrank();
    }

    function testcanClaimSchedule() public {
        assertEq(tokenVesting.balanceOf(alice), 0);

        vm.startPrank(alice);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 1000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 20000 ether);
        assertEq(tokenVesting.scheduleClaimed(alice, 1622551248, 0, 1000, 1, true, 20000 ether), true);
    }

    function testCanOnlyClaimOnce() public {
        vm.startPrank(alice);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 1000, 1, true, 20000 ether);
        vm.expectRevert(TokenVestingMerkle.AlreadyClaimed.selector);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 1000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 20000 ether);
    }

    function testProofMustBeValid() public {
        vm.startPrank(alice);

        // Pass wrong number of tokens
        vm.expectRevert(TokenVestingMerkle.InvalidProof.selector);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 1000, 1, true, 30000 ether);

        // Pass invalid proof
        aliceProof[0] = 0xca6d546259ec0929fd20fbc9a057c980806abef37935fb5ca5f6a179718f1481;

        vm.expectRevert(TokenVestingMerkle.InvalidProof.selector);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 1000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 0);
    }

    function testCannotClaimWithoutTokens() public {
        vm.startPrank(deployer);
        tokenVesting.withdraw(1000000 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(address(tokenVesting)), 0);

        vm.startPrank(alice);
        vm.expectRevert("TokenVesting: cannot create vesting schedule because of insufficient tokens in contract");
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 1000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.scheduleClaimed(alice, 1622551248, 0, 1000, 1, true, 20000 ether), false);
    }
}
