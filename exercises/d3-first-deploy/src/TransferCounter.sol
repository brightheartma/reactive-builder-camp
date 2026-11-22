// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title D3 监控合约。只计数，不请求回调。
/// @notice 订阅 Ethereum Sepolia 上某一个 ERC-20 的 `Transfer`。
///         本地测试通过不等于 Lasna 上已经触发过 `react()`。
/// @dev 依赖 reactive-lib-omni v0.1.0。`SYSTEM`、`REACTIVE_IGNORE`、`onlySystem`
///      和 `receive()` 都来自这版基类，不使用旧的 `vm` 修饰符或 `Callback` 事件。
contract TransferCounter is AbstractReactive {
    error ZeroToken();
    error ZeroLimit();

    /// @notice 每计一次匹配的 Transfer 就发出。Lasna 上这条日志所在的交易才是系统触发的 react 交易。
    event Counted(address indexed token, uint256 amount, uint256 originTxHash, uint256 count);

    /// @notice Ethereum Sepolia。来自起源与目标链文档表。
    uint256 public constant SEPOLIA_CHAIN_ID = 11_155_111;

    /// @notice `keccak256("Transfer(address,address,uint256)")`。
    uint256 public constant TRANSFER_TOPIC_0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    address public immutable token;

    /// @notice 构造时传入的次数上限。练习步骤使用 3，这是教学参数，不是协议常量。
    uint256 public immutable reactLimit;

    /// @notice 还可以计数的次数。降到 0 时用与订阅完全相同的参数退订。
    uint256 public remaining;

    /// @notice 已经计数的次数。
    uint256 public count;

    /// @notice 最近一次被计数的源链交易哈希，来自 `LogRecord.txHash`，不是 Lasna 交易哈希。
    uint256 public lastOriginTxHash;

    /// @notice 最近一次 `react()` 所在的 Lasna 区块号，是执行时的 `block.number`。
    uint256 public lastReactBlock;

    /// @notice 本地记录的订阅状态。节点里的真实订阅读不回来，这个值只反映本合约自己的退订调用。
    bool public subscribed;

    /// @param token_ 只订阅这个合约。零地址会匹配该链上所有合约，本练习不用。
    /// @param limit_ 计满这么多次就退订。传 0 会在订阅前回滚。
    constructor(address token_, uint256 limit_) payable {
        if (token_ == address(0)) revert ZeroToken();
        if (limit_ == 0) revert ZeroLimit();

        token = token_;
        reactLimit = limit_;
        remaining = limit_;

        SYSTEM.subscribe(
            SEPOLIA_CHAIN_ID,
            token_,
            TRANSFER_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        subscribed = true;
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        // 对不上就返回。回滚也会被系统收费，所以这里不用 revert 当过滤器。
        if (remaining == 0) return;
        if (log_.chainId != SEPOLIA_CHAIN_ID) return;
        if (log_.contractAddress != token) return;
        if (log_.topic0 != TRANSFER_TOPIC_0) return;
        // 标准 Transfer 有 3 个 topic：签名、from、to。数量在 data。
        if (log_.opCode != 3 || log_.data.length != 32) return;

        uint256 amount = abi.decode(log_.data, (uint256));
        count += 1;
        remaining -= 1;
        lastOriginTxHash = log_.txHash;
        lastReactBlock = block.number;
        emit Counted(log_.contractAddress, amount, log_.txHash, count);

        if (remaining == 0) {
            SYSTEM.unsubscribe(
                SEPOLIA_CHAIN_ID,
                token,
                TRANSFER_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            subscribed = false;
        }
    }

    /// @notice 用合约余额结清系统合约记下的欠款。欠款为 0 时不转出。
    function coverDebt() external {
        _coverDebt();
    }
}
