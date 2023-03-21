// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Token } from "../contracts/Token.sol";
import { TokenVesting } from "../contracts/TokenVesting.sol";

contract DevScript is Script {
    string constant mnemonic = "test test test test test test test test test test test junk";

    function run() public {
        (address deployer,) = deriveRememberKey(mnemonic, 0);
        vm.startBroadcast(deployer);

        Token token = new Token("Test Token", "TT", 18, 100_000_000 ether);
        TokenVesting tokenVesting = new TokenVesting(address(token), "Virtual Test Token", "vTT");

        console.log("TokenVesting is at: %s", address(tokenVesting));
        console.log("Native Token is at: %s", address(token));

        vm.stopBroadcast();
    }
}
