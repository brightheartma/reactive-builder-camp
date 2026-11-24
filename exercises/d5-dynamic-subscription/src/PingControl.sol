// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @notice Sepolia 上的控制源。只有部署者能发出 Ping 和 Stop。
/// @dev 停止之后两种函数都回滚，因此不会再发出日志。
contract PingControl {
    error NotOwner();
    error Stopped();

    event Ping(uint256 indexed nonce);
    event Stop(uint256 indexed nonce);

    address public immutable owner;
    uint256 public pingNonce;
    bool public stopped;

    constructor() {
        owner = msg.sender;
    }

    /// @notice 发出一次可被计数的 Ping。nonce 从 1 起。
    function ping() external {
        if (msg.sender != owner) revert NotOwner();
        if (stopped) revert Stopped();
        pingNonce += 1;
        emit Ping(pingNonce);
    }

    /// @notice 发出唯一一次 Stop。nonce 固定为 1。
    function stop() external {
        if (msg.sender != owner) revert NotOwner();
        if (stopped) revert Stopped();
        stopped = true;
        emit Stop(1);
    }
}
