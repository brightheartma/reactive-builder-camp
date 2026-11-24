// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test, Vm } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { PingControl } from "../src/PingControl.sol";
import { DynamicWatcher } from "../src/DynamicWatcher.sol";

/// @dev 放在系统合约地址上的桩。只记录订阅和退订。
contract MockSystem {
    struct Sub {
        uint256 chainId;
        address source;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    Sub[] public subs;
    Sub[] public unsubs;

    function subscribe(
        uint256 chainId,
        address source,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        uint256 topic3
    ) external {
        subs.push(Sub(chainId, source, topic0, topic1, topic2, topic3));
    }

    function unsubscribe(
        uint256 chainId,
        address source,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        uint256 topic3
    ) external {
        unsubs.push(Sub(chainId, source, topic0, topic1, topic2, topic3));
    }

    function subscribeCount() external view returns (uint256) {
        return subs.length;
    }

    function unsubscribeCount() external view returns (uint256) {
        return unsubs.length;
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable {}
}

/// @notice 这些测试模拟系统调用。通过也不表示 Lasna 上已经触发过 react()。
contract DynamicWatcherTest is Test {
    uint256 internal constant REACTIVE_IGNORE =
        0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    address internal constant SYSTEM = 0x8888888888888888888888888888888888888888;
    uint256 internal constant SEPOLIA = 11_155_111;
    uint256 internal constant PING_TOPIC =
        0x48257dc961b6f792c2b78a080dacfed693b660960a702de21cee364e20270e2f;
    uint256 internal constant STOP_TOPIC =
        0xcb38e238b49e69e3623869d1353344c0959f480b5b0d5bdbeff071a1308cff52;

    MockSystem internal system;
    PingControl internal control;
    DynamicWatcher internal watcher;
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        MockSystem impl = new MockSystem();
        vm.etch(SYSTEM, address(impl).code);
        system = MockSystem(payable(SYSTEM));
        control = new PingControl();
        watcher = new DynamicWatcher{ value: 0.1 ether }(address(control), 4);
    }

    function test_constructorSubscribesBothTopics() public view {
        assertEq(address(watcher).balance, 0.1 ether);
        assertEq(system.subscribeCount(), 2);
        assertEq(watcher.pingLimit(), 4);
        assertEq(watcher.remaining(), 4);
        assertTrue(watcher.pingSubscribed());
        assertTrue(watcher.stopSubscribed());
        _assertSub(0, PING_TOPIC);
        _assertSub(1, STOP_TOPIC);
    }

    function test_rejectsZeroControlAndZeroLimit() public {
        uint256 before = system.subscribeCount();
        vm.expectRevert(DynamicWatcher.ZeroControl.selector);
        new DynamicWatcher(address(0), 4);
        vm.expectRevert(DynamicWatcher.ZeroLimit.selector);
        new DynamicWatcher(address(control), 0);
        assertEq(system.subscribeCount(), before);
    }

    function test_reactFromAnyoneElseReverts() public {
        vm.expectRevert(abi.encodeWithSignature("NotAuthorized(address,address)", address(this), SYSTEM));
        watcher.react(_ping(1, 0x11));
        assertEq(watcher.pingCount(), 0);
    }

    function test_twoPingsCountWithoutUnsubscribing() public {
        vm.startPrank(SYSTEM);
        watcher.react(_ping(1, 0x21));
        watcher.react(_ping(2, 0x22));
        vm.stopPrank();
        assertEq(watcher.pingCount(), 2);
        assertEq(watcher.remaining(), 2);
        assertEq(watcher.lastOriginTxHash(), 0x22);
        assertEq(system.unsubscribeCount(), 0);
        assertFalse(watcher.stopped());
    }

    function test_stopUnsubscribesBothWithExactArguments() public {
        vm.startPrank(SYSTEM);
        watcher.react(_ping(1, 0x31));
        watcher.react(_ping(2, 0x32));
        vm.roll(77);
        watcher.react(_stop(0x33));
        vm.stopPrank();

        assertEq(watcher.pingCount(), 2);
        assertTrue(watcher.stopped());
        assertFalse(watcher.pingSubscribed());
        assertFalse(watcher.stopSubscribed());
        assertEq(watcher.stopOriginTxHash(), 0x33);
        assertEq(watcher.lastReactBlock(), 77);
        assertEq(system.unsubscribeCount(), 2);
        _assertUnsub(0, PING_TOPIC);
        _assertUnsub(1, STOP_TOPIC);
    }

    function test_afterStopPingDoesNotCount() public {
        vm.startPrank(SYSTEM);
        watcher.react(_ping(1, 0x41));
        watcher.react(_stop(0x42));
        watcher.react(_ping(2, 0x43));
        vm.stopPrank();
        assertEq(watcher.pingCount(), 1);
        assertEq(system.unsubscribeCount(), 2);
    }

    function test_afterStopAnotherStopIsIdempotent() public {
        vm.startPrank(SYSTEM);
        watcher.react(_stop(0x51));
        watcher.react(_stop(0x52));
        vm.stopPrank();
        assertTrue(watcher.stopped());
        assertEq(watcher.pingCount(), 0);
        assertEq(watcher.stopOriginTxHash(), 0x51);
        assertEq(system.unsubscribeCount(), 2);
    }

    function test_hardCapUnsubscribesBothWithoutStop() public {
        DynamicWatcher capped = new DynamicWatcher(address(control), 2);
        uint256 unsubsBefore = system.unsubscribeCount();
        vm.startPrank(SYSTEM);
        capped.react(_ping(1, 0x61));
        capped.react(_ping(2, 0x62));
        capped.react(_ping(3, 0x63));
        vm.stopPrank();
        assertEq(capped.pingCount(), 2);
        assertTrue(capped.stopped());
        assertFalse(capped.pingSubscribed());
        assertFalse(capped.stopSubscribed());
        assertEq(system.unsubscribeCount(), unsubsBefore + 2);
    }

    function test_ignoresWrongContractAndMalformedLogs() public {
        vm.startPrank(SYSTEM);
        IReactive.LogRecord memory other = _ping(1, 0x71);
        other.contractAddress = address(0xBEEF);
        watcher.react(other);

        IReactive.LogRecord memory wrongChain = _ping(1, 0x72);
        wrongChain.chainId = 1;
        watcher.react(wrongChain);

        IReactive.LogRecord memory badOpcode = _ping(1, 0x73);
        badOpcode.opCode = 3;
        badOpcode.data = abi.encode(uint256(1));
        watcher.react(badOpcode);

        IReactive.LogRecord memory otherTopic = _ping(1, 0x74);
        otherTopic.topic0 = uint256(keccak256("Approval(address,address,uint256)"));
        watcher.react(otherTopic);
        vm.stopPrank();
        assertEq(watcher.pingCount(), 0);
        assertEq(system.unsubscribeCount(), 0);
    }

    function test_controlOnlyOwnerEmitsAndSecondStopDoesNot() public {
        vm.prank(stranger);
        vm.expectRevert(PingControl.NotOwner.selector);
        control.ping();

        vm.prank(stranger);
        vm.expectRevert(PingControl.NotOwner.selector);
        control.stop();

        vm.recordLogs();
        control.ping();
        control.stop();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(uint256(logs[0].topics[0]), PING_TOPIC);
        assertEq(uint256(logs[1].topics[0]), STOP_TOPIC);
        assertEq(logs[0].data.length, 0);
        assertEq(logs[1].data.length, 0);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[1].topics.length, 2);

        vm.expectRevert(PingControl.Stopped.selector);
        control.ping();
        vm.expectRevert(PingControl.Stopped.selector);
        control.stop();
    }

    function test_recordedLogsDriveWatcherUntilStop() public {
        vm.recordLogs();
        control.ping();
        control.ping();
        control.stop();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 3);

        vm.startPrank(SYSTEM);
        watcher.react(_fromLog(logs[0], 0x91));
        watcher.react(_fromLog(logs[1], 0x92));
        watcher.react(_fromLog(logs[2], 0x93));
        watcher.react(_fromLog(logs[0], 0x94));
        vm.stopPrank();

        assertEq(watcher.pingCount(), 2);
        assertTrue(watcher.stopped());
        assertEq(system.unsubscribeCount(), 2);
        assertEq(watcher.stopOriginTxHash(), 0x93);
    }

    function test_coverDebtWithNoDebtLeavesBalance() public {
        uint256 before = address(watcher).balance;
        watcher.coverDebt();
        assertEq(address(watcher).balance, before);
    }

    function _assertSub(uint256 index, uint256 topic0) internal view {
        (
            uint256 chainId,
            address source,
            uint256 gotTopic0,
            uint256 topic1,
            uint256 topic2,
            uint256 topic3
        ) = system.subs(index);
        assertEq(chainId, SEPOLIA);
        assertEq(source, address(control));
        assertEq(gotTopic0, topic0);
        assertEq(topic1, REACTIVE_IGNORE);
        assertEq(topic2, REACTIVE_IGNORE);
        assertEq(topic3, REACTIVE_IGNORE);
    }

    function _assertUnsub(uint256 index, uint256 topic0) internal view {
        (
            uint256 chainId,
            address source,
            uint256 gotTopic0,
            uint256 topic1,
            uint256 topic2,
            uint256 topic3
        ) = system.unsubs(index);
        assertEq(chainId, SEPOLIA);
        assertEq(source, address(control));
        assertEq(gotTopic0, topic0);
        assertEq(topic1, REACTIVE_IGNORE);
        assertEq(topic2, REACTIVE_IGNORE);
        assertEq(topic3, REACTIVE_IGNORE);
    }

    function _ping(uint256 nonce, uint256 txHash) internal view returns (IReactive.LogRecord memory log) {
        log.chainId = SEPOLIA;
        log.contractAddress = address(control);
        log.topic0 = PING_TOPIC;
        log.topic1 = nonce;
        log.opCode = 2;
        log.txHash = txHash;
    }

    function _stop(uint256 txHash) internal view returns (IReactive.LogRecord memory log) {
        log.chainId = SEPOLIA;
        log.contractAddress = address(control);
        log.topic0 = STOP_TOPIC;
        log.topic1 = 1;
        log.opCode = 2;
        log.txHash = txHash;
    }

    function _fromLog(Vm.Log memory entry, uint256 txHash) internal pure returns (IReactive.LogRecord memory log) {
        log.chainId = SEPOLIA;
        log.contractAddress = entry.emitter;
        log.topic0 = uint256(entry.topics[0]);
        log.topic1 = uint256(entry.topics[1]);
        log.data = entry.data;
        log.opCode = 2;
        log.txHash = txHash;
    }
}
