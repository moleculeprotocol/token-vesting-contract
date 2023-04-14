// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Token } from "../contracts/test/Token.sol";
import { TokenVestingMerkle } from "../contracts/TokenVestingMerkle.sol";
import { TokenVesting } from "../contracts/TokenVesting.sol";

contract TokenVestingMerkleTest is Test {
    Token internal token;
    TokenVestingMerkle internal tokenVesting;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address deployer = makeAddr("bighead");

    bytes32[] aliceProof = new bytes32[](1);

    bytes32 merkleRoot = 0xb936dae4b02869dad6fda9f036683f568f61b80f044b85a54ba5b8d33cfd38ab;

    function setUp() public {
        // Merkle Proof for alice
        aliceProof[0] = 0xe4064973401585fcc2fff84b897ca50d10912a843cfcceb373f198206ea29ccc;

        vm.startPrank(deployer);
        token = new Token("Test Token", "TT", 18, 1000000 ether);

        // Iniate TokenVestingMerkle with the merkle root from the example MerkleTree `samples/merkleTree.json`
        tokenVesting = new TokenVestingMerkle(IERC20Metadata(token), "Virtual Test Token", "vTT", merkleRoot);

        token.transfer(address(tokenVesting), 1000000 ether);
        vm.stopPrank();
    }

    function testcanClaimSchedule() public {
        vm.warp(1622551240);

        assertEq(tokenVesting.balanceOf(alice), 0);

        vm.startPrank(alice);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 20000 ether);
        assertEq(tokenVesting.scheduleClaimed(alice, 1622551248, 0, 2630000, 1, true, 20000 ether), true);
    }

    function testCanOnlyClaimOnce() public {
        vm.warp(1622551240);

        vm.startPrank(alice);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 20000 ether);
        vm.expectRevert(TokenVestingMerkle.AlreadyClaimed.selector);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 20000 ether);
    }

    function testProofMustBeValid() public {
        vm.warp(1622551240);
        vm.startPrank(alice);

        // Pass wrong number of tokens
        vm.expectRevert(TokenVestingMerkle.InvalidProof.selector);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 30000 ether);

        // Pass invalid proof
        aliceProof[0] = 0xca6d546259ec0929fd20fbc9a057c980806abef37935fb5ca5f6a179718f1481;

        vm.expectRevert(TokenVestingMerkle.InvalidProof.selector);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 0);
    }

    function testCannotClaimWithoutTokens() public {
        vm.warp(1622551240);

        vm.startPrank(deployer);
        tokenVesting.withdraw(1000000 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(address(tokenVesting)), 0);

        vm.startPrank(alice);
        vm.expectRevert(TokenVesting.InsufficientTokensInContract.selector);
        tokenVesting.claimSchedule(aliceProof, 1622551248, 0, 2630000, 1, true, 20000 ether);
        vm.stopPrank();

        assertEq(tokenVesting.scheduleClaimed(alice, 1622551248, 0, 2630000, 1, true, 20000 ether), false);
    }
}
