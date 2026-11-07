# Git分支状态

核对：2026-11-07。本页记录集成代码和分支用途；完整实时指针以Git为准，历史分支引用不代表运行多套世界。

## 当前工作区与主线

根项目检出`codex/world-space-actions`，本阶段共同空间与最小行动交付在此保留、推送，未自动合并main。main已集成`codex/sparse-world-execution`的通用参与索引、环境/健康稀疏执行、术语入口与测试工具。最新代码提交为`f166cdb4360e91055a3f942cedf66ae446f2301e`，随后只有顶层架构、术语、验证及状态文档整理；main/origin/main同步后以实际Git记录为准。集成从原main `eff27a7dcf77031a4084258cc688bbb3616b64e4`快进，保留完整开发历史。

本机完整覆盖与代码审查范围见[BASELINE](baseline.md)，来源和保护工作审计见[集成QA](../qa/20261107_mainline_cleanup.md)。起点main `b3ae3399d24e01975d231cd000c0af342740070b`的CI42365643089已在真实提交检查点核success；新阶段分支完整本机check通过，分支推送CI未核验，不在推送后主动轮询。当前任务和未提交状态只看[HANDOFF](handoff.md)。

当前登记工作树只有根目录；没有额外引擎或等待进程。临时证据和任务前89份文件备份位于忽略目录`logs/mainline_cleanup_20261107_184537/`，不作为公共运行依赖。

## 保留分支用途

| 分支 | 已知来源提交 | 用途 |
|---|---|---|
| `codex/world-space-actions` | `fa45228`实现、`5fd6e31`审查修复、`f50f0a8`最终受检代码/测试及后续证据文档 | 基础建设第一阶段交付，当前根工作区检出；推送分支，不自动合并main |
| `main` | `f166cdb4360e91055a3f942cedf66ae446f2301e`及后续纯文档提交 | 唯一集成主线；本阶段分支尚未合入 |
| `codex/sparse-world-execution` | 原远端`3f694262ecc1086a5de3554683f63cb156d4029f`，本地另含已整理提交 | 已合入main的历史开发引用，不形成另一条待开发队列；本轮只推送main |
| `codex/world-engine-finish` | `ffe7e8c705d2d7259dfb77dcfba3dd0a64c9c61c` | 旧环境主线集成记录，已在main历史 |
| `codex/world-engine` | `2483a3771bc9f469509293a514fb0a059eefe095` | 旧开发起点，已在main历史 |
| `codex/drawing-ring-use` | `8b8457ee3fe70c19e2c23ccda1ce7ff500a6830f` | 已完成功能历史，已在main |
| `codex/private-artifact-exchange` | `a29314667f6a743fd3177b0a5190c810c2b6650b` | 已完成功能历史，已在main |
| `codex/world-view-continuity` | `945891cc977a60ecb9a499574b33784da9f5cca1` | 已完成视图连续性历史，已在main |
| `codex/field-contest` | `4e17c5c165cf8fca9ef884a111aa1c3ca35f445f` | 仅本地旧争环WIP；仍使用根43/旧迁移链，不是当前根52的待发布成果，隔离保留 |

同名本地和origin引用不是两条开发路线，origin/HEAD不是额外分支。本轮不删除历史引用、强推或改GitHub默认分支/保护设置。

## 隔离草稿

命名stash `424f956d280fb390d17e1f6dd879f3614b51a430`保留4份原环境缓存/温度及测试草稿，不应用、不删除，不纳入当前运行或公共提交。逐字备份与原元数据仍在`logs/world_engine_finish/protected-wip/`；原95份验收证据在`logs/world_engine_finish/validation-artifacts/`。旧实验移植是独立的新开发范围，不因本轮整理自动启动。
