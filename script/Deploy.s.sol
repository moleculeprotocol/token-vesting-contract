// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Token } from "../contracts/Token.sol";
import { TokenVesting } from "../contracts/TokenVesting.sol";

contract DeployScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Set the address of the native token here
        address nativeToken = 0x9A66cea9d042394f2a2ccbE9a0635cac7CeE5219;

        TokenVesting tokenVesting = new TokenVesting(IERC20Metadata(nativeToken), "Virtual Test Token", "vTT");

        console.log("TokenVesting is at: %s", address(tokenVesting));
        console.log("Native Token is at: %s", nativeToken);

        vm.stopBroadcast();
    }
}
