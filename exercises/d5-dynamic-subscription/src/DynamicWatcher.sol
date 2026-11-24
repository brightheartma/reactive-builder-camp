// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title 运行中按 Stop 事件退订的监控合约。不请求回调。
/// @notice 本地测试通过不等于 Lasna 上已经出现系统交易。
/// @dev 依赖 reactive-lib-omni v0.1.0。`react()` 里直接调用 `SYSTEM.unsubscribe`，
///      六个参数必须和订阅时相同。不使用旧的 `vm` 修饰符或 `Callback` 事件。
contract DynamicWatcher is AbstractReactive {
    error ZeroControl();
    error ZeroLimit();

    event PingCounted(uint256 indexed nonce, uint256 originTxHash, uint256 pingCount);
    event StopAccepted(uint256 indexed nonce, uint256 originTxHash);
    event AllUnsubscribed(uint256 pingCount);

    uint256 public constant SEPOLIA_CHAIN_ID = 11_155_111;

    /// @dev `keccak256("Ping(uint256)")`。
    uint256 public constant PING_TOPIC_0 =
        0x48257dc961b6f792c2b78a080dacfed693b660960a702de21cee364e20270e2f;

    /// @dev `keccak256("Stop(uint256)")`。
    uint256 public constant STOP_TOPIC_0 =
        0xcb38e238b49e69e3623869d1353344c0959f480b5b0d5bdbeff071a1308cff52;

    address public immutable control;

    /// @notice 最多计数多少次 Ping。练习步骤传 4。这是教学参数，不是协议常量。
    uint256 public immutable pingLimit;

    uint256 public pingCount;
    uint256 public remaining;
    bool public stopped;
    bool public pingSubscribed;
    bool public stopSubscribed;
    uint256 public lastOriginTxHash;
    uint256 public lastReactBlock;
    uint256 public stopOriginTxHash;

    /// @param control_ 唯一允许发出 Ping 和 Stop 的 Sepolia 合约。
    /// @param pingLimit_ Ping 硬上限。到达上限时连同 Stop 订阅一起退掉。
    constructor(address control_, uint256 pingLimit_) payable {
        if (control_ == address(0)) revert ZeroControl();
        if (pingLimit_ == 0) revert ZeroLimit();
        control = control_;
        pingLimit = pingLimit_;
        remaining = pingLimit_;
        _subscribePing();
        _subscribeStop();
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        // 已经停过就直接离开。第二次 Stop 或迟到的 Ping 不再计数，也不再退订。
        if (stopped) return;
        if (log_.chainId != SEPOLIA_CHAIN_ID || log_.contractAddress != control) return;

        if (log_.topic0 == STOP_TOPIC_0) {
            // Stop(uint256 indexed nonce)：两个 topic，data 为空。
            if (log_.opCode != 2 || log_.data.length != 0) return;
            _unsubscribeAll();
            stopped = true;
            stopOriginTxHash = log_.txHash;
            lastReactBlock = block.number;
            emit StopAccepted(log_.topic1, log_.txHash);
            return;
        }

        if (log_.topic0 != PING_TOPIC_0) return;
        if (log_.opCode != 2 || log_.data.length != 0) return;
        if (remaining == 0) return;

        pingCount += 1;
        remaining -= 1;
        lastOriginTxHash = log_.txHash;
        lastReactBlock = block.number;
        emit PingCounted(log_.topic1, log_.txHash, pingCount);

        // 停止事件没来时，硬上限把两条订阅都拆掉，避免控制订阅一直收费。
        if (remaining == 0) {
            _unsubscribeAll();
            stopped = true;
            emit AllUnsubscribed(pingCount);
        }
    }

    /// @notice 欠款为 0 时不转出余额。
    function coverDebt() external {
        _coverDebt();
    }

    function _subscribePing() internal {
        SYSTEM.subscribe(SEPOLIA_CHAIN_ID, control, PING_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        pingSubscribed = true;
    }

    function _subscribeStop() internal {
        SYSTEM.subscribe(SEPOLIA_CHAIN_ID, control, STOP_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        stopSubscribed = true;
    }

    function _unsubscribeAll() internal {
        if (pingSubscribed) {
            SYSTEM.unsubscribe(
                SEPOLIA_CHAIN_ID, control, PING_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
            pingSubscribed = false;
        }
        if (stopSubscribed) {
            SYSTEM.unsubscribe(
                SEPOLIA_CHAIN_ID, control, STOP_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
            stopSubscribed = false;
        }
    }
}
