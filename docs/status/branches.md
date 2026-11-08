# Git分支状态

核对：2026-11-08。本页记录集成代码和分支用途；完整实时指针以Git为准，历史分支引用不代表运行多套世界。

## 当前工作区与主线

main已从`2e6b6a61caf11b5560c15a97f1a58cb156a7300b`快进并推送到`eb330ee9c38fa3a5cc72004372ddeefd70409b1e`，完整包含通用建筑与组合空间。合并前核CI42457788038的完整headSha为d00bac且success；该受检代码至集成点只有Markdown差异。本轮阶段整合沿`codex/framework-consolidation`整理文档并归入同一主线，实际指针以Git为准。

分支祖先核对显示全部已完成本地/远端开发分支均在main历史，唯一未合入本地分支是下述旧争环WIP，没有其他待合并正式成果。具体证据见[BASELINE](baseline.md)。

只操作根工作树；保护分支和命名stash不应用/删除。工具进程以HANDOFF为准，临时日志、截图和存档不作为公共运行依赖。

## 保留分支用途

| 分支 | 已知来源提交 | 用途 |
|---|---|---|
| `codex/framework-consolidation` | 基于`eb330ee`，仅Markdown | 主线合并后的阶段盘点及现有主计划整理，不含新阶段代码 |
| `codex/general-buildings` | 最终代码`d00bac9`、证据`eb330ee` | 通用建筑与组合空间已完整快进合入并推送main |
| `codex/world-space-actions` | `fa45228`实现、`5fd6e31`审查修复、`f50f0a8`最终受检代码/测试及后续证据文档 | 基础建设第一阶段，已快进合入并推送main |
| `main` | 包含`eb330ee9c38fa3a5cc72004372ddeefd70409b1e`及阶段整合文档 | 唯一集成主线；共同空间、通用建筑与此前已完成框架均在其中 |
| `codex/sparse-world-execution` | 原远端`3f694262ecc1086a5de3554683f63cb156d4029f`，本地另含已整理提交 | 已合入main的历史开发引用，不形成另一条待开发队列；本轮只推送main |
| `codex/world-engine-finish` | `ffe7e8c705d2d7259dfb77dcfba3dd0a64c9c61c` | 旧环境主线集成记录，已在main历史 |
| `codex/world-engine` | `2483a3771bc9f469509293a514fb0a059eefe095` | 旧开发起点，已在main历史 |
| `codex/drawing-ring-use` | `8b8457ee3fe70c19e2c23ccda1ce7ff500a6830f` | 已完成功能历史，已在main |
| `codex/private-artifact-exchange` | `a29314667f6a743fd3177b0a5190c810c2b6650b` | 已完成功能历史，已在main |
| `codex/world-view-continuity` | `945891cc977a60ecb9a499574b33784da9f5cca1` | 已完成视图连续性历史，已在main |
| `codex/field-contest` | `4e17c5c165cf8fca9ef884a111aa1c3ca35f445f` | 仅本地旧争环WIP；仍使用根43/旧迁移链，不是当前根53的待发布成果，隔离保留 |

同名本地和origin引用不是两条开发路线，origin/HEAD不是额外分支。本轮不删除历史引用、强推或改GitHub默认分支/保护设置。

## 隔离草稿

命名stash `424f956d280fb390d17e1f6dd879f3614b51a430`保留4份原环境缓存/温度及测试草稿，不应用、不删除，不纳入当前运行或公共提交。逐字备份与原元数据仍在`logs/world_engine_finish/protected-wip/`；原95份验收证据在`logs/world_engine_finish/validation-artifacts/`。旧实验移植是独立的新开发范围，不因本轮整理自动启动。
