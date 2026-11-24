# D4：跨链回调三步走

这是官方 starter 的教学练习，不是自选项目，也不是大额转账预警。源链和目标链都用 Ethereum Sepolia，Reactive 侧用 Lasna。这次只做本地测试。下面标了「会发送」的命令现在不要执行。

来源是 https://github.com/ethpanda-org/reactive-builder-camp ，commit `87675f45bdaf7b944028bd6231e463f869b453c8`。差异写在 [exercises/d4-callback/UPSTREAM.md](../exercises/d4-callback/UPSTREAM.md)。Solidity 文件头是 MIT。官方仓库没有单独的 LICENSE 文件。

2026-11-24 的 [Origins and Destinations](https://dev.reactive.network/origins-and-destinations) 里，Ethereum Sepolia 的 callback proxy 是 `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4`。Base Sepolia 是另一个地址，这次不用，也不补 Base Sepolia 的币。

依赖是官方 `foundry.lock` 里的 reactive-lib-omni `v0.1.0`（`3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8`）。回调用 `requestCallbackV_1_0`。`Callback` 事件在这版接口里标成弃用，脚本不发它。`CampCallback` 继承 `AbstractCallback`，`onEvent` 的第一个参数是 `address`，并同时带 `onlyServiceProvider` 和 `onlyCallbackSender`。

## 现在就做：本地测试

工作区有未提交改动就停，不要 `reset`。

```bash
cd /Users/johnma/reactive-camp-d3
git status --short
git fetch origin
git checkout cursor/d4-callback-2b05
cd exercises/d4-callback
forge install --no-git \
  foundry-rs/forge-std@v1.11.0 \
  Reactive-Network/reactive-lib-omni@v0.1.0
forge test
```

`forge install` 必须在 `exercises/d4-callback` 里执行。助手环境用 Forge 1.10.0、Solidity 0.8.29 跑过，结果是 `9 passed, 0 failed`。你的 `1.7.1-monad-v1.0.0` 没有在这里重装。测试失败就停，不要部署。

这 9 个测试模拟整条链路：订阅、低于阈值不回调、系统调用后由模拟 proxy 注入地址并记到 `count`、直接调用被 `NotAuthorized` 拒绝、假的 reactive 地址被 `CallbackNotAuthorized` 拒绝、请求载荷里的第一个地址仍是 `address(0)`、两次达标后退订且第三次不再回调、外人不能 `ping`。它们不是链上交易。

## 官方模板改了什么

官方 `Deploy.s.sol` 每一步都执行 `vm.envUint("PRIVATE_KEY")`。原样跑就必须把私钥放进 `.env`。这里改成 `vm.startBroadcast()`，签名只来自命令行的 `--account d3-test`。`.env.example` 没有私钥字段。`verify.sh` 会丢掉环境里误放的 `PRIVATE_KEY`。不要执行带 `--private-key` 的命令，也不要把密码发到聊天里。

官方 `CampOrigin.ping` 是公开的。任何人都能发事件。低于阈值的事件不减少 `remaining`，也不会退订，但每次 `react()` 仍收费。这份副本改成只有部署者能 `ping`。模板本身有次数上限：`remaining` 到 0 时用同一组参数退订。`.env.example` 把 `LIMIT` 设为 1，所以一笔达标 Ping 之后就退订。脚本里没写环境变量时仍默认 5，部署时要让 `.env` 里的 `LIMIT=1` 生效。`topUp` 只改剩余次数，不会重新订阅。不要用它恢复监听。

没有自动补款，也没有跨链桥。

## 以后才部署，现在不要发这些交易

先重新 `cast balance`。模板预算是 Lasna 预存 `0.5` lREACT（`REACTIVE_FUND`）和 Sepolia 回调预存 `0.02` ETH（`CALLBACK_FUND`），再加各笔部署和一笔 `ping` 的 gas。这不是已经核实够用的余额。任一笔不够就停。

密码只在本机 `--account d3-test` 提示时输入。每条「会发送」的命令都带 `--broadcast`。不要先 `source` 一个含私钥的 `.env`。

1. 会发送。Ethereum Sepolia。不附带 `--value`。部署 `CampOrigin`，部署者成为唯一能 `ping` 的人。把输出填进 `ORIGIN_ADDR`。
2. 会发送。Lasna。附带 `REACTIVE_FUND`。部署 `CampReactive` 并订阅刚部署的源合约。把输出填进 `REACTIVE_ADDR`。
3. 会发送。Ethereum Sepolia。附带 `CALLBACK_FUND`。用 Sepolia proxy 和 `REACTIVE_ADDR` 部署 `CampCallback`。这个地址填错就只能重新部署。把输出填进 `CALLBACK_ADDR`。
4. 会发送。Lasna。不附带 `--value`。`setRecipient`，把回调合约告诉 Reactive 合约。顺序不能反：回调合约的授权地址在构造时就固定了。
5. 会发送。Ethereum Sepolia。不附带 `--value`。只调用一次 `ping(500)`。500 不小于阈值 100。发完不要再 ping。
6. 只读。`bash script/verify.sh` 打印源链 Ping、Lasna `lastReactBlock`、目标链 `Handled`。这三条才是课程要的交易证据。本地测试不能代替它们。
7. 只读预检，不是失败交易。对已部署的 `CampCallback` 做 `cast call ... "onEvent(address,uint256,uint256,uint256)"`，调用者不是 proxy，预期回滚 `NotAuthorized`。终端报错可以截图。不要为了截图再发一笔会失败的 `cast send`。

地址都等上面的输出再填，不要猜。课程提交等这三笔链上交易齐了再做。现在停在 `forge test`。
