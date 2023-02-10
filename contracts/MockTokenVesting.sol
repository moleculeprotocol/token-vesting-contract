// contracts/TokenVesting.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./TokenVesting.sol";

/**
 * @title MockTokenVesting
 * WARNING: use only for testing and debugging purpose
 */
contract MockTokenVesting is TokenVesting {
    uint256 mockTime = 0;

    constructor(address token_, string memory _name, string memory _symbol, uint8 _decimals) TokenVesting(token_, _name, _symbol, _decimals) { }

    function setCurrentTime(uint256 _time) external {
        mockTime = _time;
    }

    function getCurrentTime() internal view virtual override returns (uint256) {
        return mockTime;
    }
}
