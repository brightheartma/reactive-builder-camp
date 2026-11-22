// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test, Vm } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { TestToken } from "../src/TestToken.sol";
import { TransferCounter } from "../src/TransferCounter.sol";

/// @dev 放在系统合约地址上的桩。只记录订阅和退订，不连接任何网络。
contract MockSystem {
    struct Sub {
        uint256 chainId;
        address token;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    Sub public lastSub;
    Sub public lastUnsub;
    uint256 public subscribeCount;
    uint256 public unsubscribeCount;

    function subscribe(
        uint256 chainId,
        address token,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        uint256 topic3
    ) external {
        subscribeCount += 1;
        lastSub = Sub(chainId, token, topic0, topic1, topic2, topic3);
    }

    function unsubscribe(
        uint256 chainId,
        address token,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        uint256 topic3
    ) external {
        unsubscribeCount += 1;
        lastUnsub = Sub(chainId, token, topic0, topic1, topic2, topic3);
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable {}
}

/// @notice 这些测试模拟系统合约调用 `react()`。它们通过也不表示 Lasna 上已经发生过系统交易。
contract TransferCounterTest is Test {
    /// @dev 与 reactive-lib-omni v0.1.0 的 AbstractReactive.REACTIVE_IGNORE 相同。
    uint256 internal constant REACTIVE_IGNORE =
        0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    address internal constant SYSTEM = 0x8888888888888888888888888888888888888888;
    uint256 internal constant SEPOLIA = 11_155_111;
    uint256 internal constant TOPIC0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    uint256 internal constant LIMIT = 2;

    MockSystem internal system;
    TestToken internal token;
    TransferCounter internal counter;
    address internal alice = makeAddr("alice");

    function setUp() public {
        MockSystem impl = new MockSystem();
        vm.etch(SYSTEM, address(impl).code);
        system = MockSystem(payable(SYSTEM));

        token = new TestToken(alice, 10 ether);
        counter = new TransferCounter{ value: 0.1 ether }(address(token), LIMIT);
    }

    function test_constructorSubscribesOnlyToThisToken() public view {
        assertEq(address(counter).balance, 0.1 ether);
        assertEq(counter.reactLimit(), LIMIT);
        assertEq(counter.remaining(), LIMIT);
        assertEq(counter.count(), 0);
        assertTrue(counter.subscribed());
        assertEq(system.subscribeCount(), 1);

        (
            uint256 chainId,
            address subscribedToken,
            uint256 topic0,
            uint256 topic1,
            uint256 topic2,
            uint256 topic3
        ) = system.lastSub();
        assertEq(chainId, counter.SEPOLIA_CHAIN_ID());
        assertEq(subscribedToken, address(token));
        assertEq(topic0, counter.TRANSFER_TOPIC_0());
        assertEq(topic1, REACTIVE_IGNORE);
        assertEq(topic2, REACTIVE_IGNORE);
        assertEq(topic3, REACTIVE_IGNORE);
    }

    function test_rejectsZeroTokenAndZeroLimitBeforeSubscribe() public {
        uint256 before = system.subscribeCount();
        vm.expectRevert(TransferCounter.ZeroToken.selector);
        new TransferCounter(address(0), LIMIT);
        vm.expectRevert(TransferCounter.ZeroLimit.selector);
        new TransferCounter(address(token), 0);
        assertEq(system.subscribeCount(), before);
    }

    function test_reactFromAnyoneElseReverts() public {
        vm.expectRevert(
            abi.encodeWithSignature("NotAuthorized(address,address)", address(this), SYSTEM)
        );
        counter.react(_log(address(token), 1 ether, 0x11));
        assertEq(counter.count(), 0);
    }

    function test_systemReactCountsACompliantTransfer() public {
        vm.roll(42);
        vm.prank(SYSTEM);
        counter.react(_log(address(token), 1 ether, 0x22));

        assertEq(counter.count(), 1);
        assertEq(counter.remaining(), LIMIT - 1);
        assertEq(counter.lastOriginTxHash(), 0x22);
        assertEq(counter.lastReactBlock(), 42);
        assertTrue(counter.subscribed());
        assertEq(system.unsubscribeCount(), 0);
    }

    function test_ignoresNonTargetAndMalformedLogs() public {
        vm.startPrank(SYSTEM);
        counter.react(_log(address(0xBEEF), 1 ether, 0x31));

        IReactive.LogRecord memory wrongTopic = _log(address(token), 1 ether, 0x32);
        wrongTopic.topic0 = uint256(keccak256("Approval(address,address,uint256)"));
        counter.react(wrongTopic);

        IReactive.LogRecord memory wrongChain = _log(address(token), 1 ether, 0x33);
        wrongChain.chainId = 1;
        counter.react(wrongChain);

        IReactive.LogRecord memory wrongOpcode = _log(address(token), 1 ether, 0x34);
        wrongOpcode.opCode = 1;
        counter.react(wrongOpcode);

        IReactive.LogRecord memory shortData = _log(address(token), 1 ether, 0x35);
        shortData.data = bytes("");
        counter.react(shortData);
        vm.stopPrank();

        assertEq(counter.count(), 0);
        assertEq(counter.remaining(), LIMIT);
        assertEq(system.unsubscribeCount(), 0);
    }

    function test_limitUnsubscribesAndFurtherCallsDoNotCount() public {
        vm.startPrank(SYSTEM);
        counter.react(_log(address(token), 1 ether, 0x41));
        counter.react(_log(address(token), 2 ether, 0x42));
        counter.react(_log(address(token), 3 ether, 0x43));
        vm.stopPrank();

        assertEq(counter.count(), LIMIT);
        assertEq(counter.remaining(), 0);
        assertFalse(counter.subscribed());
        assertEq(system.unsubscribeCount(), 1);
        assertEq(counter.lastOriginTxHash(), 0x42);

        (
            uint256 chainId,
            address subscribedToken,
            uint256 topic0,
            uint256 topic1,
            uint256 topic2,
            uint256 topic3
        ) = system.lastUnsub();
        (
            uint256 subChain,
            address subToken,
            uint256 subTopic0,
            uint256 subTopic1,
            uint256 subTopic2,
            uint256 subTopic3
        ) = system.lastSub();
        assertEq(chainId, subChain);
        assertEq(subscribedToken, subToken);
        assertEq(topic0, subTopic0);
        assertEq(topic1, subTopic1);
        assertEq(topic2, subTopic2);
        assertEq(topic3, subTopic3);
    }

    function test_selfTransferKeepsBalanceAndMatchesCounter() public {
        assertEq(token.balanceOf(alice), 10 ether);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(address(0), 1 ether);

        vm.recordLogs();
        vm.prank(alice);
        assertTrue(token.transfer(alice, 1 ether));
        assertEq(token.balanceOf(alice), 10 ether);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(token));
        assertEq(logs[0].topics.length, 3);
        assertEq(uint256(logs[0].topics[0]), counter.TRANSFER_TOPIC_0());
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(alice))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), 1 ether);

        IReactive.LogRecord memory log;
        log.chainId = SEPOLIA;
        log.contractAddress = logs[0].emitter;
        log.topic0 = uint256(logs[0].topics[0]);
        log.topic1 = uint256(logs[0].topics[1]);
        log.topic2 = uint256(logs[0].topics[2]);
        log.data = logs[0].data;
        log.opCode = 3;
        log.txHash = 0x99;

        vm.prank(SYSTEM);
        counter.react(log);
        assertEq(counter.count(), 1);
        assertEq(counter.lastOriginTxHash(), 0x99);
    }

    function test_coverDebtWithNoDebtLeavesBalance() public {
        uint256 before = address(counter).balance;
        counter.coverDebt();
        assertEq(address(counter).balance, before);
    }

    function _log(address emitter, uint256 amount, uint256 txHash)
        internal
        view
        returns (IReactive.LogRecord memory log)
    {
        log.chainId = SEPOLIA;
        log.contractAddress = emitter;
        log.topic0 = TOPIC0;
        log.topic1 = uint256(uint160(alice));
        log.topic2 = uint256(uint160(alice));
        log.data = abi.encode(amount);
        log.opCode = 3;
        log.txHash = txHash;
    }
}
