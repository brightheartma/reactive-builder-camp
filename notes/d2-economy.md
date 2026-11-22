# D2：react() 的费用

这篇只记 Lasna 上三次只读查询，以及 [Economy](https://dev.reactive.network/economy) 和 [Reactive Contracts](https://dev.reactive.network/reactive-contracts) 里对得上的说明。查询在助手的环境里完成，用的是 cast 1.10.0，时间是 2026-11-22 21:04:29–21:04:39（Asia/Shanghai）。不是在用户的 Mac 上跑的。课程还没有提交。

系统合约是 `0x8888888888888888888888888888888888888888`。下面三个数文档写明所有者可以改。它们是这次读到的值，不是永久标价。这里也没有测量 gas price，所以不算某一笔要付多少 lREACT。

## 读到的参数

```bash
cast call 0x8888888888888888888888888888888888888888 "_gasPriceCoeffPer1000()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
```

```text
1000
```

```bash
cast call 0x8888888888888888888888888888888888888888 "_extraGas()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
```

```text
100000 [1e5]
```

```bash
cast call 0x8888888888888888888888888888888888888888 "_maxChargeGas()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
```

```text
50000 [5e4]
```

`[1e5]` 和 `[5e4]` 是 cast 对 100000 和 50000 的写法。Economy 页把系统合约的初始系数写成 1000，初始附加 gas 写成 100000，初始结算预算写成 50000。这次读数和那三组初始值一样。页面同时写明所有者可以改，所以换一天要重新查询。

`_maxChargeGas` 不进入费用公式。它是系统调用合约 `pay()` 做结算时的 gas 预算。

## 1. react 的费用怎么算

Economy 页的公式是 `fee = p_base * C * (g_used + K)`。

- `p_base` 取 `tx.gasprice` 和 `block.basefee` 里较大的一个，也就是 `max(tx.gasprice, block.basefee)`。
- `C` 是 `_gasPriceCoeffPer1000` 除以 1000。这次读数是 1000，所以 `C` 是 1。
- `g_used` 是这次执行实际消耗的 gas。
- `K` 是 `_extraGas`。这次读数是 100000。

因此按这次的参数，费用是 `max(tx.gasprice, block.basefee) * (g_used + 100000)`。固定的 100000 是 gas 数量，还要乘上当时的价格，才变成 Lasna 原生币。Lasna 的原生币是 lREACT。Economy 页把 Reactive 侧的原生币写成 REACT，指的是这条链自己的币。

这次 `C = 1`，系数没有把费用放大或缩小。附加的 100000 gas 则每笔都在。很短的 `react()` 和做了不少事的 `react()`，差别在 `g_used`；这一项两边都有。

每次 `react()` 都走系统合约的 `trigger`。欠款检查在最前，执行在中间，按实际消耗计费在执行之后。扣款发生在同一笔交易里，付给提交这次通知的验证者。没有一笔具体交易的 gas price 和 `g_used`，就不能写出应付的 lREACT 数额。

## 2. balance、reserves、debt

这三个数各管一件事。

- `balance` 是业务合约自己手里的原生币。
- `reserves` 是系统合约替它记着的预付额度，只能拿来付费。
- `debt` 是系统合约记下的、还没付的费用。

收费先花 reserves。reserves 用完才开始记 debt。`depositTo` 先把欠款清掉，剩下的再记进 reserves，所以欠款和预付不会同时留着。balance 跟这两项分开。

往合约地址普通转一笔，只增加 balance。它不自动清债，也不会变成 reserves。要动用这笔余额，得另走 `pay()` 或自己暴露的 `coverDebt()`。收费时如果 reserves 已经空了，系统会在同一笔交易里调用 `pay()`，按当时的欠款从 balance 里要钱。这次读到的 `_maxChargeGas` 是 50000，就是这次 `pay()` 调用的 gas 预算。自定义的 `pay()` 超出预算，或者余额不够，结算失败，欠款就留着。基类已经写了 `pay()`，自己再写一版很容易超出这个预算。

`pay()` 在同一笔交易里成功时，这笔费用不会留下欠款。`pay()` 失败，或者根本没有把余额交出去，`debt` 就会大于 0。只要 `debt > 0`，系统在还没花钱之前就不再调用 `react()`。合约不是大声报错停住，而是不再收到事件，直到欠款回到 0。

普通转入之后，钱还在合约里。系统不会因为这笔钱躺在 balance 里就继续投递。欠着的时候，要么用 `depositTo` 记到系统那一侧，要么由合约自己把 balance 交出去。没有后一条路时，转进去的钱花不到欠款上，合约会一直停着。

## 3. revert 收不收费，设计上怎么办

`react()` 里 revert，系统会接住，发出 `ReactiveContractReverted`，并且按已经烧掉的 gas 收费。计费发生在执行之后，所以回滚省不掉这笔费用。公式里的 `K` 仍然要加。对不上的日志用 `return` 提前离开，只是少烧一些 `g_used`，免不掉这次读到的 100000 附加 gas。Reactive Contracts 页把「用 revert 当过滤器」写成会照样计费；对不上就让函数走完。

所以订阅尽量窄。订阅只能做相等匹配，而且至少要有一个具体条件。合约地址用零地址，会匹配那条链上所有合约，每一笔进来的 `react()` 都要付 `g_used + K`。处理次数用完就退订；退订的六个参数必须和订阅时完全一致，否则订阅还在，费用也还在。合约里留着付得起费的钱。`pay()` 保持基类那份短实现，好让结算落在 50000 gas 的预算里。

这次能确定的有三件：

- 公式的形状，以及 2026-11-22 那次读到的三个参数。
- `debt > 0` 时，系统不再调用 `react()`。
- revert 仍按已经消耗的 gas 收费，附加的 100000 gas 也不免除。

还不能确定某一笔要付多少 lREACT，因为没有那笔交易的 gas price 和 `g_used`。参数以后变了，用上面同一组调用再读一次。
