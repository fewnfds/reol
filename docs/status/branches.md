# Git 分支状态

核对：2026-11-07。本页是核对时的快照，不替代实时`git status`；旧分支指针保留历史，不表示游戏同时运行多套世界。当前完成/待验以[接续](handoff.md)和[本包QA](../qa/20261107_world_engine_finish.md)为准。

## 本轮工作树与保护

- 项目根工作树暂在`codex/world-engine`，HEAD `2483a3771bc9f469509293a514fb0a059eefe095`。四份原环境草稿已按原SHA256核对并保存到命名stash，根工作树已干净；不要将草稿自动套到当前引擎。
- 隔离工作树`logs/world_engine_finish/dev`在`codex/world-engine-finish`，受检代码`6137481a07ec98b372e32ca857e546f1e1b07ee1`，最终本机完整回归已通过，收尾文档提交后合并。
- 本地与远端`main`最后核查均为`b5e1f3e0f3a0974b0ca771b66372b2aae4143355`，是最终代码的祖先，待验收后快进并推送。没有合并旧争环实验。

原草稿的命名stash为`preserved-env-drafts-before-world-engine-merge-20261107`，对象ID `424f956d280fb390d17e1f6dd879f3614b51a430`。逐字备份、原SHA256及stash元数据保存在本机`logs/world_engine_finish/protected-wip/`；它们不属于当前已验代码，不入库、不自动应用。原修改文件为环境场缓存、温度状态及各自测试；其中温度组件的已提交版已在本轮改变，恢复草稿必须人工比对移植。

## 各分支用途

| 本地分支 | 核对提交 | 用途与关系 |
|---|---|---|
| `main` | `b5e1f3e0f3a0974b0ca771b66372b2aae4143355` | 默认主线，待本轮验收后快进。 |
| `codex/world-engine-finish` | `6137481a07ec98b372e32ca857e546f1e1b07ee1` | 本次世界引擎普通接管与主线收尾的受检代码；另有收尾记录提交。 |
| `codex/world-engine` | `2483a3771bc9f469509293a514fb0a059eefe095` | 本包起点；其历史已包含在finish中，不再并行开发旧引擎。 |
| `codex/drawing-ring-use` | `8b8457ee3fe70c19e2c23ccda1ce7ff500a6830f` | 已包含在finish祖先历史的旧器物工作，不是合并阻塞。 |
| `codex/private-artifact-exchange` | `a29314667f6a743fd3177b0a5190c810c2b6650b` | 已包含在finish祖先历史的旧私人交换工作。 |
| `codex/world-view-continuity` | `945891cc977a60ecb9a499574b33784da9f5cca1` | 已包含在finish祖先历史的旧视图连续性工作。 |
| `codex/field-contest` | `4e17c5c165cf8fca9ef884a111aa1c3ca35f445f` | 只有本地的旧争环WIP，有独有提交，不在finish祖先中，保留且不合入。 |

同名本地和`origin/`跟踪引用不是两条开发路线，`origin/HEAD`也不是额外分支。上表旧分支是否继续保留仅影响Git指针；本包不删除分支、不强推、不改GitHub默认分支设置。主线合并、工作树切换及证据保全完成后再更新本页事实。
