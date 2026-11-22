// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice 练习用的最小 ERC-20。铸造只发生在构造函数里。
/// @dev 使用 OpenZeppelin ERC20，而不是手写余额表。decimals 沿用基类的 18。
contract TestToken is ERC20 {
    /// @param recipient 构造时收到全部铸造量的地址。不要用零地址。
    /// @param amount 铸造的最小单位数量。1000 枚是 `1000 * 10**18`。
    constructor(address recipient, uint256 amount) ERC20("D3 Test Token", "D3T") {
        _mint(recipient, amount);
    }
}
