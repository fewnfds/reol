# Git分支状态

核对：2026-11-10。本页记录集成代码和分支用途；完整实时指针以Git为准，历史分支引用不代表运行多套世界。

## 当前工作区与主线

`main`和`origin/main`已按用户授权快进并推送至`839ff88f1b7fee240d0c798f533314a3ae446430`，包括通用SL、事件/植物、环境、行动及后续镜头/诊断/缓行/FPS/连续呈现和压力Demo。该SHA的CI42776609463已核completed/success，最终生产/测试祖先为c60a2be；详细证据见[BASELINE](baseline.md)。

当前`codex/sparse-runtime-dispatch`承接调研da90e3b，落实共同运行与人物执行：显式同步/纯读取、到期及失效候选、原领域工作条件。准确提交/验证看BASELINE；空间导航和呈现规模仍在原计划。旧开发分支已集成的不再构成待合并队列；本轮不删除引用、不应用隔离stash，工具停点看[HANDOFF](handoff.md)。

## 保留分支用途

| 分支 | 已知来源提交 | 用途 |
|---|---|---|
| `codex/sparse-runtime-dispatch` | 基于调研da90e3b | 当前共同运行/人物执行包；未自动合入main，验证看BASELINE |
| `codex/performance-architecture-audit` | da90e3b，基于main839ff88 | 前性能调查与计划文档；生产改造由当前分支承接 |
| `codex/presentation-stress-demo` | 最终生产/测试c60a2be，证据839ff88 | 已快进合入并推送main；839ff88完整CI42776609463 success |
| `codex/demo-slowdown-fix` | 缓行最终b364870、FPS最终ac3dca3、文档29c50dc | 两个代码SHA完整CI均success；已随呈现/压力历史合入main |
| `codex/demo-playtest-fixes` | 基于main `7def7d2`；简单修复`87262ff`、工具最终`aa4f1a1` | 镜头/外墙与独立缓行诊断分别提交，已合入main；两者完整CI通过 |
| `codex/unit-actions-integration` | 基于环境最终`337ea13`；主体`68fff8b`、最终生产/测试`0856eff` | 第5阶段实现、主审修复与本机试玩验收收尾并推送；已合入main，0856eff完整CI通过 |
| `codex/environment-composition` | 基于`3880802`；主体`2ec88b7`、最终代码/测试`89f4716` | 环境组合及主审修复推送；22组定向/原生停开通过，最终HEAD337ea13 / CI42659346260失败，checkpoint末位漂移由行动包修复；已随行动历史合入main，证据见BASELINE/HANDOFF |
| `codex/world-events-plants` | 基于`66f56b9`；主体`801d71e`、最终生产`45f140b`、最终测试`13d675e` | 承接SL；全局事件、会话规则与植物已接普通Main并推送，13d675e完整CI通过；已随行动历史合入main，证据见BASELINE |
| `codex/save-load-framework` | 基于main `f63844b`；主体`96a6fe0`、最终代码`d682e03` | 通用参与者/领域目录、安全保存与候选加载已推送，已随行动历史合入main；验证见BASELINE |
| `codex/adaptive-world-time` | 基于`2c4ea10`；产品/永久测试`f4257e3` | 共同时间过载降速、宿主预算、呈现和验证已交付并合入main |
| `codex/actions-node24-integration` | 基于`8cc4091`；Actions代码`dc2558b` | 官方Actions升级已合入main；架构与状态文档同步整理，准确指针以Git为准 |
| `codex/settlement-kernel` | 产品`d99ac6`、测试`38606ea`、证据`8cc4091` | 已完整快进合入并推送main，本机及同测试SHA CI均通过 |
| `codex/framework-consolidation` | 基于`eb330ee`，仅Markdown | 主线合并后的阶段盘点及现有主计划整理，不含新阶段代码 |
| `codex/general-buildings` | 最终代码`d00bac9`、证据`eb330ee` | 通用建筑与组合空间已完整快进合入并推送main |
| `codex/world-space-actions` | `fa45228`实现、`5fd6e31`审查修复、`f50f0a8`最终受检代码/测试及后续证据文档 | 基础建设第一阶段，已快进合入并推送main |
| `main` | `839ff88f1b7fee240d0c798f533314a3ae446430` | 唯一集成主线，已含后续试玩/缓行/呈现/压力历史；同SHA完整CI通过 |
| `codex/sparse-world-execution` | 原远端`3f694262ecc1086a5de3554683f63cb156d4029f`，本地另含已整理提交 | 已合入main的历史开发引用，不形成另一条待开发队列 |
| `codex/world-engine-finish` | `ffe7e8c705d2d7259dfb77dcfba3dd0a64c9c61c` | 旧环境主线集成记录，已在main历史 |
| `codex/world-engine` | `2483a3771bc9f469509293a514fb0a059eefe095` | 旧开发起点，已在main历史 |
| `codex/drawing-ring-use` | `8b8457ee3fe70c19e2c23ccda1ce7ff500a6830f` | 已完成功能历史，已在main |
| `codex/private-artifact-exchange` | `a29314667f6a743fd3177b0a5190c810c2b6650b` | 已完成功能历史，已在main |
| `codex/world-view-continuity` | `945891cc977a60ecb9a499574b33784da9f5cca1` | 已完成视图连续性历史，已在main |
| `codex/field-contest` | `4e17c5c165cf8fca9ef884a111aa1c3ca35f445f` | 仅本地旧争环WIP；仍使用根43/旧迁移链，不是当前模型的待发布成果，隔离保留 |

同名本地和origin引用不是两条开发路线，origin/HEAD不是额外分支。本轮不删除历史引用、强推或改GitHub默认分支/保护设置。

## 隔离草稿

命名stash `424f956d280fb390d17e1f6dd879f3614b51a430`保留4份原环境缓存/温度及测试草稿，不应用、不删除，不纳入当前运行或公共提交。逐字备份与原元数据仍在`logs/world_engine_finish/protected-wip/`；原95份验收证据在`logs/world_engine_finish/validation-artifacts/`。旧实验移植是独立的新开发范围，不因本轮整理自动启动。
