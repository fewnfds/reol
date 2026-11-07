# Git分支状态

核对：2026-11-07。本页是快照，不替代实时Git；分支指针保留历史，不代表运行多套世界。

## 当前工作区与主线

- 根项目已切到`main`。经验证的代码为`6137481a07ec98b372e32ca857e546f1e1b07ee1`；集成点`ffe7e8c705d2d7259dfb77dcfba3dd0a64c9c61c`已从原main `b5e1f3e0f3a0974b0ca771b66372b2aae4143355`安全快进并推送，远端完整SHA已核一致。此后仅更新收尾文档，不改变受检代码。
- `codex/world-engine-finish`保留上述集成点，已进入main历史，不作为另一套引擎继续开发。临时检出`logs/world_engine_finish/dev`已在证据保全后安全移除；当前登记工作树只有根main。
- 根四份原环境草稿已保存命名stash `424f956d280fb390d17e1f6dd879f3614b51a430`，不自动应用。stash内容与原SHA256及逐字备份再次相同，备份和元数据在`logs/world_engine_finish/protected-wip/`。

实际快进记录在本机`logs/world_engine_finish/merge-result.json`，本包95份日志/图像等证据保全在`logs/world_engine_finish/validation-artifacts/`；它们不入Git。

## 保留分支用途

| 分支 | 核对提交/关系 | 用途 |
|---|---|---|
| `main` | 集成点`ffe7e8c`及后续收尾文档 | 当前唯一主线，根项目正常开发/运行入口。 |
| `codex/world-engine-finish` | `ffe7e8c705d2d7259dfb77dcfba3dd0a64c9c61c` | 本次集成留档，已合入main。 |
| `codex/world-engine` | `2483a3771bc9f469509293a514fb0a059eefe095` | 本轮起点与旧开发指针，历史已在main，不继续并行旧模型。 |
| `codex/drawing-ring-use` | `8b8457ee3fe70c19e2c23ccda1ce7ff500a6830f` | 旧器物工作，已在main历史。 |
| `codex/private-artifact-exchange` | `a29314667f6a743fd3177b0a5190c810c2b6650b` | 旧私人交换工作，已在main历史。 |
| `codex/world-view-continuity` | `945891cc977a60ecb9a499574b33784da9f5cca1` | 旧视图连续性工作，已在main历史。 |
| `codex/field-contest` | `4e17c5c165cf8fca9ef884a111aa1c3ca35f445f` | 仅本地的旧争环WIP，有独有提交，未合入、不删除。 |

同名本地和origin引用不是两条开发路线，origin/HEAD不是额外分支。本包不强推、删除历史分支或改GitHub默认分支设置。后续若清理已合分支，只清指针，先核外部协作和引用；不要把旧实验再整枝合回当前架构。
