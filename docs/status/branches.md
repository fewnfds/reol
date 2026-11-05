# Git 分支状态

核对：2026-11-05。本文是核对时的快照，不替代实时 `git status`；以下保留、清理或整合均是建议，不是执行授权。

## 当前工作区

- 唯一登记的工作树是项目根目录，当前分支为 `codex/world-engine`。
- 当前 HEAD 是 `bbd4303eb2ae477015dd1d9a40b170562c40a4d8`，其上游 `origin/codex/world-engine` 指向同一提交，核对时本地领先/落后均为 0。
- 远端实际有 5 条分支，本地有 6 条：本地多出的 `codex/field-contest` 没有远端上游。同名本地分支和 `origin/` 跟踪引用不是两条不同的开发路线。`origin/HEAD` 是指向默认分支的符号引用，不另计分支。
- GitHub 默认分支是 `main`，当前还指向较早的基线，尚未包含当前开发分支的后续工作。默认分支落后不代表玩家同时运行两个世界。

核对时还有四处未提交改动，均不在下表所列的提交 SHA 中：

- [环境场缓存](../../scripts/sim/environment_field_cache.gd)
- [温度状态](../../scripts/sim/environment_temperature_state.gd)
- [环境场缓存测试](../../tests/sim/test_environment_field_cache.gd)
- [温度状态测试](../../tests/sim/test_environment_temperature_state.gd)

这四处工作区差异合计 940 行新增、95 行删除；未提交不代表已验证或已推送，后续操作必须先保护这些改动。

## 各分支与当前 HEAD 的关系

表内数字依次为“当前 HEAD 独有提交数 / 该分支独有提交数”，按提交祖先关系统计，并非文件或功能数量。除 `codex/field-contest` 外，各分支与 HEAD 的 merge-base 均是表中该分支的提交本身。对应的同名远端分支核对时均与本地 SHA 相同。

| 本地分支 | 末次提交完整 SHA | HEAD 独有 / 分支独有 | 判断与建议 |
|---|---|---:|---|
| `main` | `b5e1f3e0f3a0974b0ca771b66372b2aae4143355` | 95 / 0 | 远端默认分支和旧基线；保留。后续按项目审查流程，在完成适用验证后决定如何更新，不能将目前的旧默认页误当最新游戏。 |
| `codex/drawing-ring-use` | `8b8457ee3fe70c19e2c23ccda1ce7ff500a6830f` | 85 / 0 | 旧器物功能分支，提交已在当前历史中；确认外部引用和协作需要后，可考虑清理本地及远端指针。 |
| `codex/private-artifact-exchange` | `a29314667f6a743fd3177b0a5190c810c2b6650b` | 84 / 0 | 旧私人器物交换分支，提交已在当前历史中；确认外部引用后可考虑清理指针。 |
| `codex/world-view-continuity` | `945891cc977a60ecb9a499574b33784da9f5cca1` | 82 / 0 | 旧世界视图连续性分支，提交已在当前历史中；确认外部引用后可考虑清理指针。 |
| `codex/world-engine` | `bbd4303eb2ae477015dd1d9a40b170562c40a4d8` | 0 / 0 | 当前开发分支；保留，当前工作区和未提交环境改动以此提交为起点。 |
| `codex/field-contest` | `4e17c5c165cf8fca9ef884a111aa1c3ca35f445f` | 81 / 1 | 本地争环实验 WIP，有独立提交且未推送；保留，不直接删除或合并。 |

末次提交分别为：`main` 的工具诊断文档（2026-11-04 07:41）、`drawing-ring-use` 的工具与回归验证文档（10:02）、`private-artifact-exchange` 的私人交换功能（10:42）、`world-view-continuity` 的世界视图修复（11:24）、`field-contest` 的实验保存（17:27），以及 `world-engine` 的暂停时推进中断修复（2026-11-05 12:34）；时间均为 UTC+08:00。

`codex/field-contest` 与 HEAD 的 merge-base 是 `6892a967bbebe7d548754a489f3c0c99f9a9627f`。它的独有提交相对此共同起点改动 26 个文件，新增 1553 行、删除 44 行；`git cherry` 未将该提交判为当前分支的等价补丁。它包含争环领域代码、测试以及与共同时间、区域模拟和存档重叠的旧改动。未来如需采用，应针对当时的当前架构逐项评估和移植，不能把这份未完成实验算成当前可玩功能。

祖先关系只说明旧提交已包含在历史中，不保证它们的代码在 HEAD 中仍逐行不变。保留可追溯的 Git 历史和暂存实验，与只维护一套当前运行世界模型并不冲突。

本次审计同步并核对了远端分支引用，未 prune、删除、合并或切换分支，未提交、推送或查询 CI；清理或更新须先核对届时的实时状态和实际授权。
