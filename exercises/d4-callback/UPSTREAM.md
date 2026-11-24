# 来源

这份练习复制自官方模板仓库：

https://github.com/ethpanda-org/reactive-builder-camp

快照 commit：`87675f45bdaf7b944028bd6231e463f869b453c8`（2026-11-09，`Add backup group contact QR`）。

该仓库没有单独的 LICENSE 文件。Solidity 源码头部是 `SPDX-License-Identifier: MIT`。

相对这份快照，只改了三处：

- `script/Deploy.s.sol` 不再读取 `PRIVATE_KEY`，签名交给 `forge script --account`。
- `.env.example` 不包含私钥字段。`script/verify.sh` 会丢掉误放进环境的 `PRIVATE_KEY`。
- `src/CampOrigin.sol` 的 `ping` 只有部署者能调用。官方原件是公开函数，任何人都能持续触发。
