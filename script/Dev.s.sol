// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Token } from "../contracts/test/Token.sol";
import { TokenVesting } from "../contracts/TokenVesting.sol";

contract DevScript is Script {
    string constant MNEMONIC = "test test test test test test test test test test test junk";

    function run() public {
        (address deployer,) = deriveRememberKey(MNEMONIC, 0);
        vm.startBroadcast(deployer);

        Token token = new Token("Test Token", "TT", 18, 100_000_000 ether);
        TokenVesting tokenVesting = new TokenVesting(IERC20Metadata(token), "Virtual Test Token", "vTT");

        console.log("TokenVesting is at: %s", address(tokenVesting));
        console.log("Native Token is at: %s", address(token));

        vm.stopBroadcast();
    }
}
