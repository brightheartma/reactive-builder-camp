# D1 用例：大额 Transfer 预警

这是一份自拟教学设计，用来回答 D1 的四个问题。`TestToken`、`TransferAlertRegistry` 和「单笔至少 1000 枚」都是设计参数，不是链上事实。

下面这些都还没有发生：编写合约、部署、订阅、充值、发送交易、把本页提交到课程、获得评分。卡片在仓库里的路径是 `notes/d1-use-case.md`。第 0 周记录仍见 [week-00.md](week-00.md)，本页不改它。

文档核对日期是 2026-11-22。支持链和费用以当天读到的页面为准，真正部署前要再看一遍。

- [Reactive Contracts](https://dev.reactive.network/reactive-contracts)
- [Origins and Destinations](https://dev.reactive.network/origins-and-destinations)
- [Economy](https://dev.reactive.network/economy)
- 回调鉴权还对照了 [Callback Contracts](https://dev.reactive.network/callback-contracts)

## 简图

```mermaid
flowchart LR
  src["Ethereum Sepolia: 计划中的 TestToken Transfer"]
  rn["Reactive Lasna: react 过滤后才请求回调"]
  dst["Base Sepolia: 计划中的 TransferAlertRegistry"]
  src --> rn --> dst
```

纯文本备用：

```text
Ethereum Sepolia
计划中的 TestToken，事件 Transfer
        |
        v
Reactive Lasna
react 解析数量，排除零地址，达到阈值才请求回调
        |
        v
Base Sepolia
计划中的 TransferAlertRegistry，记下预警并发出事件
```

达不到阈值，或者 `from` / `to` 有一边是零地址的日志，停在 Lasna，不请求回调。图上没有跨链桥，也没有资产转移。

## 1. 监听哪条链、哪个合约、什么事件

源链是 Ethereum Sepolia。2026-11-22 的起源与目标链页面把测试网和主网分开，并写明两边不要混用。该页测试网表里，Ethereum Sepolia 的 chain id 是 `11155111`，并且可以作为 Origin。

合约是计划自己部署的测试 ERC-20，名字用 `TestToken`。地址还没有，本页不编造地址，也不借用官方案例合约。地址没定之前，订阅不能写成「这个指定合约」。文档里合约条件用 `address(0)` 表示任意合约；那会听整条 Sepolia 上的匹配事件，和「只听自己这份代币」不是一回事，所以本设计不用它。

事件是这份代币上的 `Transfer(address,address,uint256)`。订阅里的 `topic0` 用这个签名的哈希。常见 ERC-20 把 `from` 和 `to` 标成 indexed，数量放在非 indexed 的 `data` 里，这样的日志有 3 个 topic。这是写合约前的假设。真正的解码以部署时那份 ABI 为准：谁被 indexed，谁就在 topic 里，其余在 `data` 里。

处理合约跑在 Reactive Lasna，不跑在 Sepolia 上。同一张测试网表里，Lasna 的 chain id 是 `5318007`。Lasna 是 Reactive 这条链，不是 Transfer 的源链。

## 2. 满足什么条件触发

订阅只做相等匹配。文档写明没有范围、比较或按位过滤，一个订阅里也不能写「或」。因此「数量大于等于 1000 枚」和「地址不是零地址」都不能放进 `subscribe` 的条件。

计划中的订阅是三条确定条件加三个主题通配：

- 链：Ethereum Sepolia，`11155111`
- 合约：将来部署出来的那个 `TestToken` 地址
- `topic0`：`Transfer(address,address,uint256)` 的签名哈希
- `topic1` 到 `topic3`：`REACTIVE_IGNORE`

主题通配用的是 `REACTIVE_IGNORE`，不是数字 0。文档说明 topic 里的 0 可以是真实值，ERC-20 铸造的 `Transfer` 就是 `from` 为零地址。这次读的 reactive-contracts 页只给出了 `REACTIVE_IGNORE` 这个名字，没有给出它的数值，所以这里不写死常量。

`react()` 收到日志后再做业务判断。按当时的代币 ABI 取出数量。在 decimals 为 18 的假设下，阈值是单笔至少 1000 枚，也就是原始数量大于等于 `1000 * 10**18`。decimals 若不是 18，这个原始整数要重算。铸造和销毁也排除：在 `from`、`to` 确实位于 topic 的前提下，任一边是零地址就跳过。

对不上的日志直接返回。文档说明把 `revert` 当成过滤器是错的：系统会接住异常，发出 `ReactiveContractReverted`，并且仍按烧掉的 gas 收费。

两条判断都通过，才向目标链请求回调。阈值、合约名都还只是设计参数。

## 3. 在哪条链做什么动作

目标链是 Base Sepolia。同一张测试网表里它的 chain id 是 `84532`，可以作为 Destination。源链和目标链都是测试网，符合「不要把主网和测试网混在一次回调里」。

目标合约计划叫 `TransferAlertRegistry`，目前没有部署。回调里要记下的内容是：代币地址、原始数量、发送方、接收方、来源标识，然后再发出一条预警事件。事件名字也是自拟的，链上还没有这条事件。

这个动作只写记录和事件。没有自动短信，没有网页推送，不转移代币，不经过跨链桥。源链上的 `Transfer` 在日志出现时已经生效。Lasna 上的 `react()` 和 Base Sepolia 上的回调发生在那之后，不能撤销或拦住那笔源链交易。

回调要同时满足两道检查，文档把它们写成缺一不可：

- 调用者必须是目标链的 callback proxy，也就是这笔费用的服务提供者。少了这一道，任何人都能直接调用登记函数，并随便填一个来源地址。
- 载荷的第一个 `address` 会被网络改写成发起回调的 reactive 合约地址，不管编码时放的是什么占位符。这一道要等于部署登记合约时授权的那个 reactive 合约。少了这一道，网络上别的 reactive 合约也能经合法 proxy 调用过来。

2026-11-22 从起源与目标链页面抄下的协议地址如下，它们不是 `TestToken`，也不是钱包：

| 角色 | 链 | chain id | 文档中的 callback proxy |
| --- | --- | --- | --- |
| 源链，本设计不拿它做回调校验 | Ethereum Sepolia | 11155111 | `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` |
| Reactive 链 | Reactive Lasna | 5318007 | `0x8888888888888888888888888888888888888888` |
| 目标链，登记合约要认的服务提供者 | Base Sepolia | 84532 | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` |

reactive-contracts 页把系统合约也写在 `0x8888888888888888888888888888888888888888`。`react()` 只接受这个系统合约调用。Base Sepolia 上要认的是表里那一个 proxy，不是 Lasna 的系统合约。起源页还说回调交易由 Reactive Signer 提交、再进入 proxy。这次读到的页面没有给出 Signer 地址，所以这里不编一个。

登记合约用见过的来源标识去重，同一个标识只保留一条预警。标识怎么构造，以实际拿来编译的 ABI 为准，不能先断言 `LogRecord` 一定有 `txHash` 和 `logIndex`。2026-11-22 读到的三份公开材料并不一致：

- [reactive-contracts](https://dev.reactive.network/reactive-contracts) 页上的 `LogRecord` 使用 `txHash` 和 `logIndex`。
- [reactive-lib 主分支的 IReactive.sol](https://github.com/Reactive-Network/reactive-lib/blob/main/src/interfaces/IReactive.sol) 使用 `tx_hash` 和 `log_index`。这份源文件里这两项都在。
- 更早的 [reactive-bounties TECH.md](https://github.com/Reactive-Network/reactive-bounties/blob/main/TECH.md) 把 `react` 的参数列到 `op_code` 为止，那份签名没有交易哈希和日志序号。

若编译所用的结构里确有交易哈希和日志序号，来源标识就由源链编号、源合约地址、这两个字段组成，字段名跟那份 ABI。若那份 ABI 没有这两项，就不要补造。退路是源链编号、源合约、区块号、相关 topic 和 `data` 的哈希，但同一区块里两笔内容相同的 `Transfer` 会得到同一个标识，那不能当作唯一。本页不选一套字段名做成代码，因为合约还没写。本文也不写 Omni 或 Legacy 的具体实现。

还有一处不要混用。当前回调文档写的是：载荷第一个地址被换成发出请求的 reactive 合约地址。更早的 TECH.md 写的是换成部署者的 RVM ID。实现时只跟当时要编译的那一版，不把两种身份塞进同一个检查。

文档里的部署约束是：回调基类把授权的 reactive 地址定成不可变，填错就要重新部署。将来若按这套基类做，顺序是先部署 Sepolia 上的 `TestToken`，再部署 Lasna 上的 reactive 合约并订阅该地址，然后用这个 reactive 地址和 Base Sepolia 的 proxy 部署登记合约，再把 reactive 合约的回调接收方设成登记合约，最后分别充值。这些步骤都还没做。

## 4. 不用 Reactive 怎么做，它简单在哪里，代价是什么

不用 Reactive 时，可以用一台自己的程序听 Ethereum Sepolia 的 RPC，只看将来那个 `TestToken` 的 `Transfer`，在程序里做数量和零地址过滤，自己保存去重，再用一把私钥在 Base Sepolia 上签名，调用登记合约。这台程序要一直在线，RPC 会中断，签名账户要有 Base Sepolia 的 ETH，nonce、gas 和失败后的重试都要自己处理。也可以不用程序，在区块浏览器里看见一笔就手工抄下来。手工没有目标链上的事件，也容易漏。

Reactive 省掉的是这台常驻程序和放在程序里的热私钥。匹配的日志由网络调用 `react()`，需要时再把回调送到 Base Sepolia。合约安全、两道权限、两边充值，以及失败和债务的处理，仍然要自己做。

代价来自 [Economy](https://dev.reactive.network/economy) 页，不是一张固定价目表：

- Reactive 侧每次实际执行的 `react()` 都收费，费率为 `p_base * C * (g_used + K)`。`p_base` 取交易 gas price 和区块 base fee 里较高的一个，`C` 来自系数除以 1000，`K` 是固定附加 gas。该页写系统合约的初始系数是 1000、附加 gas 是 100000、结算 gas 预算是 50000，并写明所有者可以改。这是文档里的初始值。目标链 proxy 没有统一默认值，要向那份 proxy 查询。本文没有做链上查询，不写出现价。
- 订阅命中的每一条 `Transfer` 都会进入 `react()`，包括小额转账和铸造、销毁。过滤发生在这次执行里面，所以过滤也有成本。回调另算，记在 Base Sepolia 的登记合约上，用那条链的原生 ETH，不是 Lasna 的 lREACT。文档把 Reactive 侧的原生代币写成 REACT；Lasna 的原生币是 lREACT。
- 债务大于零时，系统合约不再调用 `react()`，callback proxy 也不再投递回调。失败的 `react()` 和失败的回调仍然收费。回调请求的 gas 下限是 100000，低于这个下限的请求会被忽略。proxy 还要先留出自己的记账和结算 gas，目标函数拿不到请求里的全部 gas。
- 从源链日志到目标链记录是异步的。支持的网络以文档表格为限。余额或储备不够、债务未清、gas 不够、目标地址上还没有合约，都会影响这次执行。不能把这条路径写成免费，也不能写成源链交易一旦成功，目标链就同步记下。

## 核对后改过的地方

原先的想法是「监听指定合约的 Transfer，在 Lasna 上按数量和零地址决定是否回调，再到 Base Sepolia 记账」。链的选择留着：三边都在测试网支持表里。改动的是过滤、鉴权、去重和费用各归哪一侧：

- 数量阈值和排除零地址放在 `react()` 里，不放进订阅条件。
- 不匹配时正常返回，不用 `revert` 过滤。
- 目标合约同时检查 proxy 和被授权的 reactive 合约。
- 来源标识等实际 ABI 确定后再拼，不先断言字段名。
- Reactive 侧和目标侧分开充值，过滤和失败都会计费。
