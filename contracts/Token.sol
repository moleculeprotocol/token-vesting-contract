// contracts/Token.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_, uint256 initialSupply) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, initialSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
