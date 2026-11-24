// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title CampOrigin — 源链上的「事件发射器」（部署在 Sepolia 等源链）
/// @notice 三步走的第 1 步：在源链发出一个事件。真实项目里这一步通常是别人的合约
///         （ERC-20 Transfer、Uniswap Sync…），这里用一个最小合约方便自己触发。
contract CampOrigin {
    /// @dev 官方模板的 ping 是公开的。这份练习副本改成只有部署者能触发，避免别人不断发出事件把 Lasna 余额扣光。
    error NotOwner();

    address public immutable owner;

    /// @dev topic0 = keccak256("Ping(address,uint256)")；who 是 indexed → topic1；value 在 data 里
    event Ping(address indexed who, uint256 value);

    constructor() {
        owner = msg.sender;
    }

    function ping(uint256 value) external {
        if (msg.sender != owner) revert NotOwner();
        emit Ping(msg.sender, value);
    }
}
