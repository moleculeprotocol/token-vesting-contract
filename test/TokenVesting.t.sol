// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { Token } from "../contracts/Token.sol";
import { MockTokenVesting } from "../contracts/MockTokenVesting.sol";

contract TokenVestingTest is Test {
    Token internal token;
    MockTokenVesting internal tokenVesting;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address deployer = makeAddr("bighead");

    function setUp() public {
        vm.startPrank(deployer);
        token = new Token("Test Token", "TT", 1000000 ether);
        tokenVesting = new MockTokenVesting(address(token));
        vm.stopPrank();
    }

    function testTokenSupply() public {
        assertEq(token.totalSupply(), 1000000 ether);
        assertEq(token.balanceOf(deployer), 1000000 ether);
    }

    function testGradualTokenVesting() public {
        uint256 baseTime = 1622551248;
        uint256 duration = 1000;
        MockTokenVesting.VestingSchedule memory vestingSchedule;

        assertEq(tokenVesting.getToken(), address(token));

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 1000 ether);

        assertEq(token.balanceOf(address(tokenVesting)), 1000 ether);
        assertEq(tokenVesting.getWithdrawableAmount(), 1000 ether);

        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 100 ether);
        vm.stopPrank();

        assertEq(tokenVesting.getVestingSchedulesCountByBeneficiary(alice), 1);

        bytes32 vestingScheduleId = tokenVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0);

        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 0);

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        tokenVesting.setCurrentTime(halfTime);

        // check that vested amount is half the total amount to vest
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 50 ether);

        // check that only beneficiary can try to release vested tokens
        vm.startPrank(bob);
        vm.expectRevert("TokenVesting: only beneficiary and owner can release vested tokens");
        tokenVesting.release(vestingScheduleId, 100 ether);
        vm.stopPrank();

        // check that beneficiary cannot release more than the vested amount
        vm.startPrank(alice);
        vm.expectRevert("TokenVesting: cannot release tokens, not enough vested tokens");
        tokenVesting.release(vestingScheduleId, 100 ether);
        vm.stopPrank();

        // release 10 tokens
        vm.startPrank(alice);
        tokenVesting.release(vestingScheduleId, 10 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 10 ether);

        // check that the vested amount is now 40
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 40 ether);

        vestingSchedule = tokenVesting.getVestingSchedule(vestingScheduleId);
        assertEq(vestingSchedule.released, 10 ether);

        // set current time after the end of the vesting period
        tokenVesting.setCurrentTime(baseTime + duration + 1);

        // check that the vested amount is 90
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 90 ether);

        // beneficiary release vested tokens (45)
        vm.startPrank(alice);
        tokenVesting.release(vestingScheduleId, 45 ether);
        vm.stopPrank();

        // owner release vested tokens (45)
        vm.startPrank(deployer);
        tokenVesting.release(vestingScheduleId, 45 ether);
        vm.stopPrank();

        // check that the number of released tokens is 100
        vestingSchedule = tokenVesting.getVestingSchedule(vestingScheduleId);
        assertEq(vestingSchedule.released, 100 ether);

        // check that the vested amount is 0
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 0 ether);

        /*
        * TEST SUMMARY
        * send tokens to vesting contract
        * create new vesting schedule (100 tokens)
        * check that vested amount is 0
        * set time to half the vesting period
        * check that vested amount is half the total amount to vest (50 tokens)
        * check that only beneficiary can try to release vested tokens
        * check that beneficiary cannot release more than the vested amount
        * release 10 tokens
        * check that the released amount is 10
        * check that the vested amount is now 40
        * set current time after the end of the vesting period
        * check that the vested amount is 90 (100 - 10 released tokens)
        * release all vested tokens (90)
        * check that the number of released tokens is 100
        * check that the vested amount is 0
       */
    }

    function testNonOwnerCannotRevokeSchedule() public {
        uint256 baseTime = 1622551248;
        uint256 duration = 1000;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 100 ether);
        vm.stopPrank();

        bytes32 vestingScheduleId = tokenVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0);

        vm.startPrank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenVesting.revoke(vestingScheduleId);
        vm.stopPrank();
    }

    function testRevokeScheduleReleasesVestedTokens() public {
        uint256 baseTime = 1622551248;
        uint256 duration = 1000;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 100 ether);

        assertEq(tokenVesting.getWithdrawableAmount(), 0);

        bytes32 vestingScheduleId = tokenVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // set time to half the vesting period
        uint256 halfTime = 1622551248 + 1000 / 2;
        tokenVesting.setCurrentTime(halfTime);

        tokenVesting.revoke(vestingScheduleId);
        assertEq(token.balanceOf(address(alice)), 50 ether);

        MockTokenVesting.VestingSchedule memory vestingSchedule = tokenVesting.getVestingSchedule(vestingScheduleId);
        assertEq(vestingSchedule.revoked, true);

        assertEq(tokenVesting.getWithdrawableAmount(), 50 ether);
    }

    function testScheduleIndexComputation() public {
        bytes32 expectedVestingScheduleId = 0x1891b47bd496d985cc84f1e264ac3dea4e3f7af4fafeb854e6cd86a41b23e7f9;

        assertEq(tokenVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0), expectedVestingScheduleId);
    }

    function testTextInputParameterChecks() public {
        uint256 baseTime = 1622551248;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);

        vm.expectRevert("TokenVesting: duration must be > 0");
        tokenVesting.createVestingSchedule(alice, baseTime, 0, 0, 1, false, 100 ether);

        vm.expectRevert("TokenVesting: slicePeriodSeconds must be >= 1");
        tokenVesting.createVestingSchedule(alice, baseTime, 0, 1, 0, false, 100 ether);

        vm.expectRevert("TokenVesting: amount must be > 0");
        tokenVesting.createVestingSchedule(alice, baseTime, 0, 1, 1, false, 0);
    }
}
