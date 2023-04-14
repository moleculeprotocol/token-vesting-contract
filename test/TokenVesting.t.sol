// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Token } from "../contracts/test/Token.sol";
import { TokenVesting } from "../contracts/TokenVesting.sol";

contract TokenVestingTest is Test {
    Token internal token;
    Token internal wrongToken;
    TokenVesting internal tokenVesting;
    TokenVesting internal tokenVesting2;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address deployer = makeAddr("bighead");

    function setUp() public {
        vm.startPrank(deployer);
        token = new Token("Test Token", "TT", 18, 1000000 ether);
        wrongToken = new Token("Wrong Token", "TT", 6, 1000000 ether);
        tokenVesting = new TokenVesting(IERC20Metadata(token), "Virtual Test Token", "vTT");
        vm.stopPrank();
    }

    function testTokenSupply() public {
        assertEq(token.totalSupply(), 1000000 ether);
        assertEq(token.balanceOf(deployer), 1000000 ether);
    }

    function testWrongToken() public {
        vm.startPrank(deployer);
        vm.expectRevert(TokenVesting.DecimalsError.selector);
        tokenVesting2 = new TokenVesting(IERC20Metadata(wrongToken), "Virtual Test Token", "vTT");
        vm.stopPrank();
    }

    function testVirtualTokenMeta() public {
        assertEq(tokenVesting.name(), "Virtual Test Token");
        assertEq(tokenVesting.symbol(), "vTT");
        assertEq(tokenVesting.decimals(), 18);
    }

    function testGradualTokenVesting() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;
        TokenVesting.VestingSchedule memory vestingSchedule;

        assertEq(address(tokenVesting.nativeToken()), address(token));

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 1000 ether);

        assertEq(token.balanceOf(address(tokenVesting)), 1000 ether);
        assertEq(tokenVesting.getWithdrawableAmount(), 1000 ether);

        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 100 ether);
        vm.stopPrank();

        assertEq(tokenVesting.holdersVestingScheduleCount(alice), 1);

        bytes32 vestingScheduleId = tokenVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0);

        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 0);

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        // check that vested amount is half the total amount to vest
        assertEq(tokenVesting.computeReleasableAmount(vestingScheduleId), 50 ether);

        // check that only beneficiary can try to release vested tokens
        vm.startPrank(bob);
        vm.expectRevert(TokenVesting.Unauthorized.selector);
        tokenVesting.release(vestingScheduleId, 100 ether);
        vm.stopPrank();

        // check that beneficiary cannot release more than the vested amount
        vm.startPrank(alice);
        vm.expectRevert(TokenVesting.InsufficientReleasableTokens.selector);
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
        vm.warp(baseTime + duration + 1);

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
        uint256 baseTime = block.timestamp + 1 weeks;
        uint256 duration = 4 weeks;

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

    function testCanOnlyBeRevokedIfRevokable() public {
        uint256 baseTime = block.timestamp + 1 weeks;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, false, 100 ether);

        bytes32 vestingScheduleId = tokenVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0);

        vm.expectRevert(TokenVesting.NotRevokable.selector);
        tokenVesting.revoke(vestingScheduleId);
        vm.stopPrank();
    }

    function testNonOwnerCannotCreateSchedule() public {
        uint256 baseTime = block.timestamp + 1 weeks;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 100 ether);
        vm.stopPrank();
    }

    function testRevokeScheduleReleasesVestedTokens() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 100 ether);

        assertEq(tokenVesting.getWithdrawableAmount(), 0);

        bytes32 vestingScheduleId = tokenVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        assertEq(token.balanceOf(address(alice)), 0 ether);

        tokenVesting.revoke(vestingScheduleId);
        assertEq(token.balanceOf(address(alice)), 50 ether);

        TokenVesting.VestingSchedule memory vestingSchedule = tokenVesting.getVestingSchedule(vestingScheduleId);
        assertEq(vestingSchedule.status == TokenVesting.Status.REVOKED, true);

        assertEq(tokenVesting.getWithdrawableAmount(), 50 ether);

        // Cannot withdraw more than available
        vm.expectRevert(TokenVesting.InsufficientTokensInContract.selector);
        tokenVesting.withdraw(51 ether);

        tokenVesting.withdraw(50 ether);
        assertEq(tokenVesting.getWithdrawableAmount(), 0);

        vm.stopPrank();

        // Alice can't release more tokens
        vm.warp(baseTime + duration);
        vm.startPrank(alice);
        vm.expectRevert(TokenVesting.ScheduleWasRevoked.selector);
        tokenVesting.release(vestingScheduleId, 50 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(address(alice)), 50 ether);
    }

    function testScheduleIndexComputation() public {
        bytes32 expectedVestingScheduleId = 0x1891b47bd496d985cc84f1e264ac3dea4e3f7af4fafeb854e6cd86a41b23e7f9;

        assertEq(tokenVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0), expectedVestingScheduleId);
    }

    function testTextInputParameterChecks() public {
        uint256 baseTime = block.timestamp + 1 weeks;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);

        vm.expectRevert(TokenVesting.InvalidDuration.selector);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, 0, 1, false, 100 ether);

        vm.expectRevert(TokenVesting.InvalidSlicePeriod.selector);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 0, false, 100 ether);

        vm.expectRevert(TokenVesting.InvalidAmount.selector);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, false, 0);

        vm.expectRevert(TokenVesting.DurationShorterThanCliff.selector);
        tokenVesting.createVestingSchedule(alice, baseTime, 5 weeks, duration, 1, false, 100 ether);
    }

    function testComputationMultipleForSchedules() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 1000 ether);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 100 ether);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration * 2, 1, true, 50 ether);
        assertEq(tokenVesting.getVestingSchedulesIds().length, 2);
        assertEq(tokenVesting.holdersVestingScheduleCount(alice), 2);
        vm.stopPrank();

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        assertEq(tokenVesting.balanceOf(alice), 150 ether);
    }

    function testClaimAvailableTokens() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 1000 ether);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 100 ether);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration * 2, 1, true, 50 ether);
        assertEq(tokenVesting.getVestingSchedulesIds().length, 2);
        assertEq(tokenVesting.holdersVestingScheduleCount(alice), 2);
        vm.stopPrank();

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        assertEq(tokenVesting.balanceOf(alice), 150 ether);

        vm.startPrank(alice);
        tokenVesting.releaseAvailableTokensForHolder(alice);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 87.5 ether);
        assertEq(token.balanceOf(address(alice)), 62.5 ether);
    }

    function testCannotClaimMoreThanAvailable() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 1000 ether);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 100 ether);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration * 2, 1, true, 50 ether);
        assertEq(tokenVesting.getVestingSchedulesIds().length, 2);
        assertEq(tokenVesting.holdersVestingScheduleCount(alice), 2);
        vm.stopPrank();

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        assertEq(tokenVesting.balanceOf(alice), 150 ether);

        vm.startPrank(alice);
        tokenVesting.releaseAvailableTokensForHolder(alice);
        vm.stopPrank();

        assertEq(tokenVesting.balanceOf(alice), 87.5 ether);
        assertEq(token.balanceOf(address(alice)), 62.5 ether);
    }

    function testVirtualTokenTotalSupplyAndBalance() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        // virtual token total supply should be 0 before any vesting schedules are created
        assertEq(tokenVesting.totalSupply(), 0);

        // virtual token balance of alice should be 0 before any vesting schedules are created
        assertEq(tokenVesting.balanceOf(address(alice)), 0);

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 100 ether);
        vm.stopPrank();

        bytes32 vestingScheduleId = tokenVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // virtual token total supply should be 100 after vesting schedule is created
        assertEq(tokenVesting.totalSupply(), 100 ether);

        // virtual token balance of alice should be 100 after vesting schedule is created
        assertEq(tokenVesting.balanceOf(address(alice)), 100 ether);

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        vm.startPrank(alice);
        tokenVesting.release(vestingScheduleId, 50 ether);
        assertEq(token.balanceOf(address(alice)), 50 ether);
        vm.stopPrank();

        // virtual token total supply should be 50 after alice has released 50 tokens
        assertEq(tokenVesting.totalSupply(), 50 ether);

        // virtual token balance of alice should be 50 after alice has released 50 tokens
        assertEq(tokenVesting.balanceOf(address(alice)), 50 ether);

        // set time to end of vesting period
        vm.warp(baseTime + duration + 1);

        assertEq(tokenVesting.balanceOf(address(alice)), 50 ether);

        vm.startPrank(alice);
        tokenVesting.release(vestingScheduleId, 50 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(address(alice)), 100 ether);
        assertEq(tokenVesting.balanceOf(address(alice)), 0);
    }

    function testNonTransferability() public {
        uint256 baseTime = block.timestamp;
        uint256 duration = 4 weeks;

        vm.startPrank(deployer);
        token.transfer(address(tokenVesting), 100 ether);
        tokenVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, 100 ether);
        vm.stopPrank();

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        assertEq(tokenVesting.balanceOf(address(alice)), 100 ether);

        vm.startPrank(alice);
        vm.expectRevert(TokenVesting.NotSupported.selector);
        tokenVesting.transfer(address(bob), 50 ether);

        vm.expectRevert(TokenVesting.NotSupported.selector);
        tokenVesting.transferFrom(address(alice), address(bob), 50 ether);

        vm.expectRevert(TokenVesting.NotSupported.selector);
        tokenVesting.approve(address(1), 50 ether);
        vm.stopPrank();
    }

    function testFuzzCreateAndRelease(uint256 amount, uint256 duration) public {
        // Assuming 1.6 Tredecillion tokens is enough for everyone
        uint256 maxTokens = 2 ** 200;
        // schedule duration between 1 day and 50 years
        uint256 maxDuration = 50 * (365 days);

        vm.assume(amount > 0 ether && amount <= maxTokens);
        vm.assume(duration > 1 weeks && duration <= maxDuration);

        uint256 baseTime = block.timestamp;

        vm.startPrank(deployer);
        Token fuzzToken = new Token("Fuzz Token", "TT", 18, amount);
        TokenVesting fuzzVesting = new TokenVesting(IERC20Metadata(fuzzToken), "Fuzz Vesting", "FV");
        fuzzToken.transfer(address(fuzzVesting), amount);
        fuzzVesting.createVestingSchedule(alice, baseTime, 0, duration, 1, true, amount);
        vm.stopPrank();

        bytes32 vestingScheduleId = fuzzVesting.computeVestingScheduleIdForAddressAndIndex(alice, 0);

        // set time to half the vesting period
        uint256 halfTime = baseTime + duration / 2;
        vm.warp(halfTime);

        uint256 releasableAmount = fuzzVesting.computeReleasableAmount(vestingScheduleId);

        vm.startPrank(alice);
        fuzzVesting.release(vestingScheduleId, releasableAmount);
        vm.stopPrank();
    }

    function testNativeTokenDecimals() public {
        vm.startPrank(deployer);
        Token customToken = new Token("6 Decimals Token", "6DT", 6, 100 ether);
        vm.expectRevert(TokenVesting.DecimalsError.selector);
        new TokenVesting(IERC20Metadata(customToken), "Vesting", "v6DT");
        vm.stopPrank();
    }
}
