# D5：用停止事件退订

选的是运行中按事件退订，不是定时 Cron，也不是把 D3 的次数上限改个名字。

Sepolia 上新部署一份 `PingControl`。只有部署者能调用 `ping()` 和 `stop()`。Lasna 上的 `DynamicWatcher` 同时订阅这两条事件。两次 `Ping` 各触发一次 `react()` 并计数。随后的 `Stop` 再触发一次 `react()`，在里面用和订阅时相同的六个参数，把 Ping 订阅和 Stop 订阅都退掉。没有回调。

另外还有一个 Ping 硬上限，练习里传 `4`。这是教学参数。两次 Ping 加一次 Stop 不会碰到它。如果一直不发 Stop，数到 4 也会把两条订阅一起拆掉，避免只留下控制订阅继续收费。

本地 `forge test` 不能代替链上完成。合约地址和交易哈希都先空着，等你自己签名广播之后再填。课程还没有提交。

官方依据是 2026-11-24 读到的 [Reactive Contracts](https://dev.reactive.network/reactive-contracts)：`react()` 里可以 `subscribe` / `unsubscribe`；退订的六个参数必须和订阅完全一致，否则订阅还在。公开课程页没有展开场景手册正文。这里按你给出的 B 选项做：收到停止事件就取消相关订阅，并且不做回调。

`main` 在这次开分支时含有 D2，不含 D3 代码。PR #3 当时仍是打开状态，没有合并。本练习不改那份 PR，也不向已部署的旧监控器发交易。

## 不要动旧的 D3 合约

2026-11-24 15:13（Asia/Shanghai），助手环境用 cast 1.10.0 做了只读查询。旧 Lasna 监控器 `0x8BA4c3e797167B1446FFb2F64C1F089b10E86A16` 当时是：

- `token()` = `0xA087cE4C3eef70B923Bd3F2f945077E06033af45`
- `subscribed()` = `true`
- `count()` = `1`
- `remaining()` = `2`
- `reactLimit()` = `3`
- 合约余额约 `0.08153` lREACT，系统记下的 `debt` 为 `0`

那枚代币当时的名字是 `D3 Test Token`。旧监控器还在听它的 `Transfer`。再转这枚币，会让旧合约再计费。本练习不调用它，也不调用旧监控器。执行前请再只读查一次 `subscribed()` 和 `remaining()`。查到的数和上面不同，以新的为准，但只要 `subscribed` 仍是 `true`，就不要转那枚币。

同一次只读里，钱包 `0x2e00e5E170DF844698d38DC7eBf9C44987D36C0f` 的 Sepolia 余额约 `0.0400` ETH，Lasna 余额约 `0.8909`。这是当时的快照，不是现在的余额。每一笔发送前都要重查。

## 0. 先在本机跑测试

不访问链。你的目录如果还有未提交改动，停，不要 `reset`。

```bash
cd /Users/johnma/reactive-camp-d3
git status --short
git fetch origin
git checkout cursor/d5-dynamic-subscription-2b05
```

分支还没合并进 `main`。`checkout` 失败就停。

```bash
cd exercises/d5-dynamic-subscription
forge install --no-git \
  foundry-rs/forge-std@v1.11.0 \
  Reactive-Network/reactive-lib-omni@v0.1.0
forge test
```

必须在这个目录里安装。依赖是 forge-std `v1.11.0`（`8e40513d678f392f398620b3ef2b418648b33e89`）和 reactive-lib-omni `v0.1.0`（`3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8`）。

助手环境用 Forge 1.10.0、Solidity 0.8.29 跑过：`12 passed, 0 failed`。你的 `1.7.1-monad-v1.0.0` 已经能编译 0.8.29，也有 `--broadcast`、`--account`、`--value`。测试不是 12 通过就停，不要部署。通过只说明本地模拟符合预期。

## 1. 只读核对

```bash
export MY_ADDR=0x2e00e5E170DF844698d38DC7eBf9C44987D36C0f
cast wallet address --account d3-test
cast chain-id --rpc-url https://ethereum-sepolia-rpc.publicnode.com
cast chain-id --rpc-url https://lasna-rpc.rnk.dev/
cast balance "$MY_ADDR" --rpc-url https://ethereum-sepolia-rpc.publicnode.com --ether
cast balance "$MY_ADDR" --rpc-url https://lasna-rpc.rnk.dev/ --ether
```

`cast wallet address` 会在你自己的终端要 keystore 密码。不要把密码发到聊天里。输出必须等于 `$MY_ADDR`。链编号必须是 `11155111` 和 `5318007`。不对就停。

Lasna 余额要能盖住后面那笔 `0.1` lREACT 的合约预存，再加部署 gas。只比 `0.1` 多一点点就停。`0.1ether` 在 Lasna 上是 0.1 lREACT，来自 omni Xfers 示例用过的附值，不是这次测出来的精确费用。Sepolia 余额是 0 也停。

## 2. Sepolia：部署控制合约

先看帮助里的 `--broadcast`。Forge 1.10.0 上，不加它会写 `Dry run enabled` 并且没有 `Deployed to:`。你这版如果帮助写明默认就会广播，就不要做 dry run。

不广播的检查：

```bash
cd exercises/d5-dynamic-subscription
forge create \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --account d3-test \
  src/PingControl.sol:PingControl
```

这一步不附带 `--value`。出现 `Deployed to:` 就说明已经发出去了，停，不要再部署一次。

确认不会误广播之后，下面这条会发送交易。链是 Ethereum Sepolia，不附带原生币。

```bash
forge create \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --account d3-test \
  --broadcast \
  src/PingControl.sol:PingControl
```

成功时看 `Deployed to:`。失败就停。

```bash
export CONTROL=
```

把 `Deployed to` 填进 `CONTROL`。不要猜。

```bash
cast call --rpc-url https://ethereum-sepolia-rpc.publicnode.com "$CONTROL" "owner()(address)"
```

预期等于 `$MY_ADDR`。不是就停。

## 3. Lasna：部署监控合约

先再查一次 Lasna 余额。不够就停。

下面这条会发送交易。链是 Lasna，附带 `--value 0.1ether`，也就是 0.1 lREACT。构造参数是刚部署的控制合约和硬上限 `4`。

```bash
forge create \
  --rpc-url https://lasna-rpc.rnk.dev/ \
  --account d3-test \
  --broadcast \
  --value 0.1ether \
  src/DynamicWatcher.sol:DynamicWatcher \
  --constructor-args "$CONTROL" 4
```

```bash
export WATCHER=
```

填入 `Deployed to`。然后只读：

```bash
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$WATCHER" "pingCount()(uint256)"
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$WATCHER" "remaining()(uint256)"
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$WATCHER" "pingSubscribed()(bool)"
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$WATCHER" "stopSubscribed()(bool)"
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$WATCHER" "stopped()(bool)"
```

预期是 `0`、`4`、`true`、`true`、`false`。`pingSubscribed` 只是合约自己的记录，节点里的订阅读不回来。

## 4. 两次 Ping，然后一次 Stop

每笔都是 Ethereum Sepolia 交易，不附带 `--value`。发之前如果 `pingCount` 已经不是你预期的数，就不要发。

第一次，会发送：

```bash
cast send \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --account d3-test \
  "$CONTROL" "ping()"
```

等 Lasna 上 `pingCount` 变成 `1`、`remaining` 变成 `3`。十分钟还不变就停，不要连着再 ping。

第二次，会发送：

```bash
cast send \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --account d3-test \
  "$CONTROL" "ping()"
```

等到 `pingCount` 为 `2`、`remaining` 为 `2`。

然后停止，会发送：

```bash
cast send \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --account d3-test \
  "$CONTROL" "stop()"
```

等到 `stopped` 为 `true`，`pingSubscribed` 和 `stopSubscribed` 都为 `false`，`pingCount` 仍是 `2`。不要再调用 `ping()` 或 `stop()`。控制合约第二次调用会回滚，但没必要多发。

## 5. 找出至少两笔系统交易

`lastReactBlock` 是 Lasna 区块，不是 Sepolia 区块。每次计数或接受 Stop 之后读它，再查该区块的日志。`transactionHash` 才是 Lasna 上那笔系统交易。

```bash
export BLOCK=
cast logs \
  --rpc-url https://lasna-rpc.rnk.dev/ \
  --address "$WATCHER" \
  --from-block "$BLOCK" \
  --to-block "$BLOCK" \
  --json \
  "PingCounted(uint256 indexed nonce,uint256 originTxHash,uint256 pingCount)"
```

两次 Ping 各做一次。Stop 换成：

```bash
cast logs \
  --rpc-url https://lasna-rpc.rnk.dev/ \
  --address "$WATCHER" \
  --from-block "$BLOCK" \
  --to-block "$BLOCK" \
  --json \
  "StopAccepted(uint256 indexed nonce,uint256 originTxHash)"
```

字段名对不上就停。拿到哈希之后：

```bash
export LASNA_TX=
cast run --rpc-url https://lasna-rpc.rnk.dev/ "$LASNA_TX"
```

`cast run` 不发送新交易。调用链里应先有 `0x8888888888888888888888888888888888888888::trigger`，再进 `react`。没有这层，就不是系统触发。自己直接调用 `react()` 会被 `onlySystem` 回滚，那种失败交易不算完成。

页面形态沿用之前核对过的：

```text
https://lasna.reactscan.net/address/$WATCHER
https://lasna.reactscan.net/tx/$LASNA_TX
```

提交课程时需要监控合约地址、至少两笔 Lasna 上的 `react` 交易，以及本页对「不会无限扣费」的说明。这些哈希还没填进去之前，课程要求还没有满足。本页不代替提交。

## 怎样避免一直扣费

- 两条订阅都钉死在新的 `PingControl` 上，不听旧代币的 `Transfer`。
- 只有部署者能发出 Ping 和 Stop。别人的交易不会在这个合约里发出事件。
- `react()` 再核对链、合约和事件。对不上就 `return`，不用 `revert` 当过滤器。
- Stop 到达时，同一笔 `react()` 退掉 Ping 和 Stop 两条订阅。参数不一致时退订会静默留着，所以合约里两条路径共用同一组参数。
- 硬上限 `4` 是后路：Stop 没来也会把两条都退掉。
- 停过之后再进来的日志直接返回，不再计数，也不再退订。
- 这些本地旗标不是节点里的订阅。停完以后不要再发 Ping。如果 `pingCount` 还在涨，说明退订没有生效，立刻停。

## 故障

`pingCount` 一直是 0：核对 `CONTROL` 是否就是构造参数，链是不是 Sepolia `11155111`。不要改去转旧代币。

突然不再触发，而且 `stopped` 仍是 `false`：查欠款。

```bash
cast call --rpc-url https://lasna-rpc.rnk.dev/ \
  0x8888888888888888888888888888888888888888 \
  "debt(address)(uint256)" "$WATCHER"
```

大于 0 就先不要再 ping。给合约转入 lREACT 只增加余额，不自动清债。余额够时才发送这一笔 Lasna 交易：

```bash
cast send --rpc-url https://lasna-rpc.rnk.dev/ --account d3-test "$WATCHER" "coverDebt()"
```

编译出现 `vm` 或 `emit Callback`：依赖不是 `reactive-lib-omni` v0.1.0。停，按第 0 步重装这两份 tag。
