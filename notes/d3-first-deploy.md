# D3：第一次在 Lasna 上触发 react()

这是监控练习，不是回调练习。合约只订阅你自己在 Ethereum Sepolia 上部署的测试 ERC-20 的 `Transfer`，计数达到上限后退出订阅。不请求目标链回调，不使用 D1 里自拟的 1000 枚门槛，也不部署到 Base Sepolia。

本地 `forge test` 通过，只说明模拟调用符合预期。它不是 Lasna 上的系统交易，课程提交也还没有做。

次数上限 `3` 是这份练习选定的教学参数，不是协议常量。测试里用的上限是 `2`，用来观察第三次调用不再计数；上链时构造参数传 `3`。

## 依赖

2026-11-22 用下面三个 tag 安装，并记下当时解析到的 commit。`foundry.lock` 只保存这张对照表。Forge 1.10.0 在没有依赖参数时不会按这个文件自动安装，所以安装命令把 tag 写全。

| 目录 | 来源 | tag | commit |
| --- | --- | --- | --- |
| `lib/forge-std` | foundry-rs/forge-std | v1.11.0 | `8e40513d678f392f398620b3ef2b418648b33e89` |
| `lib/reactive-lib-omni` | Reactive-Network/reactive-lib-omni | v0.1.0 | `3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8` |
| `lib/openzeppelin-contracts` | OpenZeppelin/openzeppelin-contracts | v5.7.0 | `cab19933c33c2ad1d4c7a84864a3601dddfd16f3` |

`reactive-lib-omni` v0.1.0 的 `AbstractReactive` 把系统合约定在 `0x8888888888888888888888888888888888888888`，`react()` 用 `onlySystem`。`AbstractPayer` 提供可收款的 `receive()`。这版接口里的 `Callback` 事件标成了弃用；本练习不发回调，也不使用旧的 `vm` 修饰符。

编译器用 Solidity `0.8.29`，和这个库的 pragma 一致。

## 0. 先看本机 Forge，先不要重装

这一步只在本机执行，不访问链。

```bash
forge --version
```

预期是印出一段版本说明。你这台 Mac 上的版本是 `1.7.1-monad-v1.0.0`。下面命令的旗标是在 Forge `1.10.0`（commit `083e22994195d6a7e3ad3104d0b57f478c9b9062`）上核对的，没有在 `1.7.1-monad-v1.0.0` 上执行过。两份版本不同，不构成重装理由。后面的部署步骤会要求先看你自己的 `forge create --help`。某个旗标不存在时停下来，不要先重装。

## 1. 更新仓库，保留现有检出

这一步只操作 git，不访问链。工作区有未提交改动时停，不要 `reset` 或 `clean`。

已经有这个仓库时：

```bash
git status --short
git fetch origin
git checkout main
git pull --ff-only origin main
```

`git status --short` 有输出就停。`pull` 不是快进也停。

这篇笔记合并进 `main` 之前，改检练习分支：

```bash
git fetch origin cursor/d3-first-deploy-2b05
git checkout cursor/d3-first-deploy-2b05
```

还没有仓库时，在一个新目录克隆，不要覆盖已有文件夹：

```bash
git clone https://github.com/brightheartma/reactive-builder-camp.git
cd reactive-builder-camp
git fetch origin cursor/d3-first-deploy-2b05
git checkout cursor/d3-first-deploy-2b05
```

合并之后，`main` 上会有同路径文件。合并前 `main` 没有这次的练习。

## 2. 安装依赖

在练习目录里执行。这一步从 GitHub 克隆依赖，不向 Sepolia 或 Lasna 发交易。不要在仓库根目录加 `--root`：2026-11-22 在 Forge 1.10.0 上那样做会报 `Library directory is not relative to the repository root`。

```bash
cd exercises/d3-first-deploy
forge install --no-git \
  foundry-rs/forge-std@v1.11.0 \
  Reactive-Network/reactive-lib-omni@v0.1.0 \
  OpenZeppelin/openzeppelin-contracts@v5.7.0
```

预期输出里有三行 `Installed forge-std v1.11.0`、`Installed reactive-lib-omni v0.1.0`、`Installed openzeppelin-contracts v5.7.0`。少一行就停。`--no-git` 表示不把依赖加成子模块；`lib/` 已被仓库忽略。

## 3. 本地编译和测试

不访问链。

```bash
forge build
forge test
```

`forge build` 预期以 `Compiler run successful` 结束，Solidity 版本是 `0.8.29`。

`forge test` 预期是 `8 tests passed, 0 failed`。覆盖的是：构造函数只订阅指定代币并向合约转入 `0.1 ether` 的余额；零地址和 0 次上限在订阅前回滚；非系统地址调用 `react()` 回滚；系统地址调用一次后计数加一；别的合约、别的 topic、别的链、topic 数量不对、`data` 长度不对都忽略；达到上限时用同一组参数退订，之后再调用不再计数；OpenZeppelin `transfer` 给自己时余额不变并发出 `Transfer`，转到零地址会回滚。

有失败就停，不要部署。这里的通过不是链上完成。

## 4. 只读核对链编号和余额

下面三条只读。2026-11-22 对这两个公开 RPC 调用 `cast chain-id`，结果是 `11155111` 和 `5318007`。

把地址放进 shell 变量。仓库里不写具体地址。

```bash
export MY_ADDR=0x你的测试地址
cast chain-id --rpc-url https://ethereum-sepolia-rpc.publicnode.com
cast chain-id --rpc-url https://lasna-rpc.rnk.dev/
cast balance "$MY_ADDR" --rpc-url https://ethereum-sepolia-rpc.publicnode.com --ether
cast balance "$MY_ADDR" --rpc-url https://lasna-rpc.rnk.dev/ --ether
```

链编号不是这两个数就停，后面的 URL 不能换到别的链上用。

余额以这次命令的输出为准。2026-11-19 的 Lasna 截图是 1.05 lREACT，当时 Sepolia 大约还有 0.04 ETH；那两个数都不是现在的余额。

`--ether` 只把最小单位按 18 位小数显示。Sepolia 上显示的是测试 ETH。Lasna 上同一面旗标显示的是 lREACT，不是 Sepolia ETH。

停的条件：

- 任一余额命令失败，或链编号不对。
- Lasna 余额小于或等于 `0.1`。后面给监控合约的预存就是 `0.1` 个 lREACT，部署交易的 gas 还要另外从钱包扣。只比 `0.1` 多一点点也停，因为还没支付部署 gas。
- Sepolia 余额是 `0`。部署 ERC-20 和一笔转账都要消耗 Sepolia ETH。具体 gas 等第 7 步的 dry run，不要用一个固定数代替。

`0.1` 这个预存不是精确报价。omni 分支的 Xfers 示例对「最多处理 10 次」使用了 `--value 0.1ether`。营速查表写过，在 Lasna gas price 为 100 gwei 时，一笔简单 `react()` 大约 0.015 lREACT。3 次计数大约落在这个量级里，`0.1` 留有余量。Economy 页的费率系数可以由所有者修改；写这篇笔记时没有查询当前系数，所以不要把 0.015 或 0.1 当成成交价。

Forge 帮助里的 `--value 0.1ether` 表示 `10^18` wei 的该链原生币。在 Lasna 上就是 0.1 lREACT。

## 5. 把测试钱包放进本机 keystore

这一步只写本机 `~/.foundry/keystores`，不广播交易。提示符里粘贴私钥，不要把它放进命令、环境变量或仓库。

```bash
cast wallet import d3-test --interactive
cast wallet address --account d3-test
```

导入时会要私钥和 keystore 密码。第二条命令再要一次密码。预期输出是一个地址，并且等于 `$MY_ADDR`。不相等就停，不要继续部署。

然后回到仓库根目录看一眼：

```bash
cd ../..
git status --short
cd exercises/d3-first-deploy
```

预期没有 keystore、`.env`、`broadcast/` 或私钥文件。有的话停，不要提交。

## 6. 先读你自己的 forge create 帮助

不访问链。

```bash
forge create --help
```

Forge 1.10.0 的帮助里有这些旗标：

- `--broadcast`：广播交易。不加它时，1.10.0 会写 `Dry run enabled, not broadcasting transaction`。
- `--value`：随交易发送的原生币，例子是 `0.1ether`。
- `--account`：使用 `~/.foundry/keystores` 里的名字。
- `--constructor-args`：构造参数。
- `--interactive` 存在，但会在提示符里输入私钥。这份步骤用 `--account`，不用 `--interactive` 部署，也不用 `--private-key`。

你的帮助里如果没有 `--broadcast`，停。不要运行 `forge create`，也不要为了补这个旗标先重装。旧版本可能默认就会广播。

## 7. Sepolia：先 dry run，再部署测试币

第 7.1 步在 Forge 1.10.0 上不广播。第 7.2 步会发送交易。

### 7.1 只读 dry run

```bash
forge create \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --account d3-test \
  src/TestToken.sol:TestToken \
  --constructor-args "$MY_ADDR" 1000000000000000000000
```

构造参数是接收铸造量的地址，以及 `1000 * 10**18` 个最小单位，也就是 1000 枚。铸造发生在构造函数里，发生在监控合约部署之前，所以这次铸造不会被计数。

Forge 1.10.0 的预期是出现 `Dry run enabled, not broadcasting transaction`，并且没有 `Deployed to:`。交易 JSON 里有十六进制 `gas`。那是这次 dry run 的估算，不是一篇笔记里的固定费用。估算乘上 gas price 之后如果已经超过第 4 步的 Sepolia 余额，停。

如果输出里已经有 `Deployed to:` 或 `Transaction hash:`，说明这次已经广播了。停，把那两个值记下来，不要再部署第二次。

### 7.2 广播部署

这一步发送交易。

```bash
forge create \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --account d3-test \
  --broadcast \
  src/TestToken.sol:TestToken \
  --constructor-args "$MY_ADDR" 1000000000000000000000
```

Forge 1.10.0 在本地链上的成功输出是三行：`Deployer:`、`Deployed to:`、`Transaction hash:`。把 `Deployed to` 存下来：

```bash
export TOKEN=0x这里换成Deployed_to的地址
```

失败或回滚就停，不要换参数反复发送。

### 7.3 只读确认

```bash
cast call --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  "$TOKEN" "balanceOf(address)(uint256)" "$MY_ADDR"
cast call --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  "$TOKEN" "decimals()(uint8)"
```

余额预期是 `1000000000000000000000`。本地 Anvil 上同一条命令还附带显示 `[1e21]`，那是 10^21 的写法。`decimals` 预期是 `18`。不对就停，不要部署监控合约。

## 8. Lasna：部署监控合约

先重复第 4 步的 Lasna 余额检查。不够就停。

### 8.1 dry run，不广播

```bash
forge create \
  --rpc-url https://lasna-rpc.rnk.dev/ \
  --account d3-test \
  --value 0.1ether \
  src/TransferCounter.sol:TransferCounter \
  --constructor-args "$TOKEN" 3
```

预期同样是 dry run 警告，没有 `Deployed to:`。`--value 0.1ether` 在这条链上是往新合约存 0.1 lREACT。构造参数是第 7 步的代币地址和教学上限 `3`。

出现 `Deployed to:` 就说明已经广播，停，不要再发一次。

### 8.2 广播部署

这一步发送交易。

```bash
forge create \
  --rpc-url https://lasna-rpc.rnk.dev/ \
  --account d3-test \
  --broadcast \
  --value 0.1ether \
  src/TransferCounter.sol:TransferCounter \
  --constructor-args "$TOKEN" 3
```

成功时同样看 `Deployer:`、`Deployed to:`、`Transaction hash:`。

```bash
export COUNTER=0x这里换成Deployed_to的地址
```

构造函数会调用 Lasna 上的系统合约 `subscribe`。裸的本地链没有这个系统合约，部署会回滚；那不能用来判断 Lasna。Lasna 上回滚就停，保留报错，不要连续重试。

合约构造函数是 `payable`，所以 `--value` 能在部署时把原生币放进合约。基类另有 `receive()`，以后也可以直接向合约地址转 lREACT。转账本身不会清掉已经记下的欠款；欠款要用 `coverDebt()`，见后面的故障说明。

### 8.3 只读确认初始状态

```bash
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$COUNTER" "count()(uint256)"
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$COUNTER" "remaining()(uint256)"
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$COUNTER" "reactLimit()(uint256)"
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$COUNTER" "subscribed()(bool)"
cast balance "$COUNTER" --rpc-url https://lasna-rpc.rnk.dev/ --ether
```

预期依次是 `0`、`3`、`3`、`true`，合约余额是 `0.1`。`count` 不是 `0` 就先不要转账，说明已经有事件被计数了。

`subscribed` 只是合约自己的记录。节点里的真实订阅读不回来。

## 9. 用一笔自转触发

只转自己的 `TestToken`。OpenZeppelin ERC-20 的 `transfer` 拒绝零地址，所以不要烧币。接收方就是 `$MY_ADDR` 自己。本地测试里，这种自转会发出 `Transfer`，余额保持不变。

先看计数，避免重复花钱。

```bash
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$COUNTER" "count()(uint256)"
```

输出不是 `0` 就停，不要再转。

### 9.1 估算 gas，只读

```bash
cast estimate \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --from "$MY_ADDR" \
  "$TOKEN" \
  "transfer(address,uint256)" \
  "$MY_ADDR" \
  1000000000000000000
```

这是 1 枚代币的最小单位。估算失败，或你判断 Sepolia 余额不够支付这笔 gas 时，停。

### 9.2 广播自转

这一步发送交易。

```bash
cast send \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --account d3-test \
  "$TOKEN" \
  "transfer(address,uint256)" \
  "$MY_ADDR" \
  1000000000000000000
```

`cast send` 会签名并发布。预期有交易哈希，并且状态成功。失败就停。不要再发第二笔来「试试」。

自己调用监控合约的 `react()` 不算完成。那个入口只接受系统合约，直接调用会回滚。

## 10. 等 Lasna 上的系统交易

只读轮询。每 30 秒一次，最多 10 分钟：

```bash
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$COUNTER" "count()(uint256)"
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$COUNTER" "remaining()(uint256)"
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$COUNTER" "lastReactBlock()(uint256)"
cast call --rpc-url https://lasna-rpc.rnk.dev/ "$COUNTER" "lastOriginTxHash()(uint256)"
```

`count` 变成 `1`、`remaining` 变成 `2` 就可以停。不要为了看更多次数再转账。上限是 3，满了会退订；退订生效前，网络上可能还有已经匹配上的日志。

10 分钟后仍是 `count = 0`，进入故障说明，不要继续转账。

`lastOriginTxHash` 是 Sepolia 那笔转账的哈希，类型在合约里是 `uint256`。`lastReactBlock` 是 `react()` 执行时的 Lasna 区块号，不是 Sepolia 区块。

## 11. 在 Reactscan 上找到合约和系统交易

这两个 URL 形态在 2026-11-22 核对过：营模板 README 使用 `https://lasna.reactscan.net/address/<地址>`；omni Xfers 说明里的示例交易 `0xcda3570e0928476b77d0a0aac1764c447cc2af56047076699dd5ce00a767a285` 打开 `https://lasna.reactscan.net/tx/<哈希>` 时，页面标题就是这笔交易。笔记没有假设浏览器上有一个名叫「内部交易」的按钮。

合约页：

```text
https://lasna.reactscan.net/address/$COUNTER
```

系统交易要从日志反查，因为 `react()` 是系统合约交易里的调用，不是你的钱包直接发到监控合约的交易。把上一节的 `lastReactBlock` 代入：

```bash
export BLOCK=这里换成lastReactBlock的十进制数字
cast logs \
  --rpc-url https://lasna-rpc.rnk.dev/ \
  --address "$COUNTER" \
  --from-block "$BLOCK" \
  --to-block "$BLOCK" \
  --json \
  "Counted(address indexed token,uint256 amount,uint256 originTxHash,uint256 count)"
```

这是只读。JSON 里这条日志的 `transactionHash` 就是 Lasna 上包含 `Counted` 的交易。字段名对不上就停，不要猜页面按钮。

```bash
export LASNA_TX=0x这里换成transactionHash
cast run --rpc-url https://lasna-rpc.rnk.dev/ "$LASNA_TX"
```

`cast run` 只重放调用，不发送新交易。预期调用链里先看到 `0x8888888888888888888888888888888888888888::trigger`，再看到你的合约的 `react`。omni Xfers 说明里的示例跟踪就是这个形状。看不到 `trigger` 调用 `react` 时，不要把这笔交易当成系统触发。

对应页面：

```text
https://lasna.reactscan.net/tx/$LASNA_TX
```

课程要求的两个链接就是上面的合约页和这笔 Lasna 交易页。提交由你自己做。这篇笔记不代替提交，也不表示已经评分。

## 故障

余额或欠款不足。`react()` 从监控合约的 lREACT 余额里付费。欠款大于 0 时系统不再投递。只读查询：

```bash
cast call --rpc-url https://lasna-rpc.rnk.dev/ \
  0x8888888888888888888888888888888888888888 \
  "debt(address)(uint256)" "$COUNTER"
cast balance "$COUNTER" --rpc-url https://lasna-rpc.rnk.dev/ --ether
```

欠款不是 0，而且合约余额足够时，可以发送一笔 `coverDebt()`。这一步会广播，余额不够就不要发：

```bash
cast send --rpc-url https://lasna-rpc.rnk.dev/ --account d3-test "$COUNTER" "coverDebt()"
```

直接把 lREACT 转到合约地址只会增加余额。已经存在的欠款仍要 `coverDebt()` 或系统的 `pay()` 才会清掉。

订阅没有生效。`count` 一直是 0、`remaining` 仍是 3。核对三件事：监控合约在 Lasna 而不是 Sepolia；构造参数里的代币地址就是 `$TOKEN`；源链 chain id 是 `11155111`。topic 是 `Transfer(address,address,uint256)`，合约里写成常量 `0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef`。订阅存在节点里，合约没有读取接口。

没有源链事件。转账回滚、转的是别的代币，或者 `transfer` 的接收方是零地址，都不会产生这次要的日志。零地址会被 OpenZeppelin 拒绝。不要改去烧币。

接口来自旧库。编译出现 `vm` 修饰符、`rnOnly`，或代码要求 `emit Callback`，说明依赖不是 `reactive-lib-omni` v0.1.0。停，不要改回旧写法。重新按第 2 步安装这三份 tag。

Forge 旗标不一致。`forge create --help` 没有 `--broadcast` 或 `--value` 时停。不要重装之后再猜命令。

## 还没有做的事

没有在 Sepolia 或 Lasna 上替你部署或转账。没有把 D3 标成课程已完成，也没有提交课程。第 0 周记录和 D1 笔记的正文没有改。
