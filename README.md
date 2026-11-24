# reactive-builder-camp

个人公开学习仓库，用来放 [Reactive Builder Camp](https://web3career.build/zh/programs/reactive-builder-camp?tab=learning) 的每日打卡和之后的练习代码。

## notes/

`notes/` 按周记下已经核实的学习事实。第 0 周准备写在 [notes/week-00.md](notes/week-00.md)。

D1 自拟用例说明（尚未实现，尚未提交课程）：[notes/d1-use-case.md](notes/d1-use-case.md)。

D2 费用说明（参数来自助手查询环境的只读调用，尚未提交课程）：[notes/d2-economy.md](notes/d2-economy.md)。

D5 动态订阅练习（本地测试已写；链上还没部署，课程也还没交）：[notes/d5-dynamic-subscription.md](notes/d5-dynamic-subscription.md)。

## 进度

- [x] 2026-11-18（上海时间）领取 0.05 Sepolia 测试 ETH，并已换取 Lasna 测试币
- [x] 2026-11-19 创建本公开仓库
- [ ] 第 0 周准备
- [ ] 课程学习

上面只勾选了已经核实的两项。第 0 周准备和课程学习都还开着。细节见 [notes/week-00.md](notes/week-00.md)。

## 提交前检查

不要把私钥、助记词或 API 密钥提交进仓库。`.gitignore` 只跳过 `.env`、`.env.*`（仍保留 `.env.example`）、系统垃圾文件和常见 keystore 目录。忽略规则不能代替安全检查，提交前需要自己看过 `git status` 和 diff。
