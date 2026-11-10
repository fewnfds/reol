# Git分支状态

核对：2026-11-10。本页记录集成代码和分支用途；完整实时指针以Git为准，历史分支引用不代表运行多套世界。

## 当前工作区与主线

2026-11-10按用户授权将`codex/unit-actions-integration`及通用SL、事件/植物、环境历史快进整合main，最终生产/测试`0856effd4b2bb135c9bae8f25cccbba0e3def8e0`。前版完整CI两项失败已复现并收尾，定向及一次静态主审通过；新SHA的CI42750266714已在后续真实提交点核completed/success；整合本身不是通过证据。Demo试玩修复与性能诊断另分支、另提交。

main已从`a4fb83a6c29e3203bf71fc1c1f950afe4906830b`快进并推送到共同结算证据提交`8cc40919599680d57e1f333f1482ebab38df7e3b`。最终产品d99ac6、测试38606ea的本机完整251组/125351检查/0失败与同测试SHA CI42508829722 success已核；至集成点仅Markdown差异，结算、建筑、共同空间均在main。

官方Actions Node24升级提交`dc2558b219cb2fbdf164c2d63371e01b0cff8226`亦已快进合入并推送main，`codex/actions-node24-integration`保留其开发引用；游戏内容和规则保持不变，接续查[HANDOFF](handoff.md)。原结算分支成为已集成历史引用，不形成待合并代码队列。

共同时间调速产品/永久测试`f4257e38a1665c08c8596028fe71c0cea0dbeab9`及QA帧驱动收尾已按用户授权快进合入main；对应产品CI42542611182完整通过，一次Sol/custom原生主审无可确认修复问题。

只操作根工作树；保护分支和命名stash不应用/删除。工具进程以HANDOFF为准，临时日志、截图和存档不作为公共运行依赖。

## 保留分支用途

| 分支 | 已知来源提交 | 用途 |
|---|---|---|
| `codex/presentation-stress-demo` | 基于29c50dc；呈现e56adac/db995598，续包e3da86a、最终代码/测试c60a2be | 连续人物/镜头及真实压力Demo；续包原身体按需积分/到期堆。前HEAD6420499的CI42769354347因夹具签名解析失败，已定向修复；续包主审及定向已完成，新HEAD完整CI待验，未合main |
| `codex/demo-slowdown-fix` | 缓行最终b364870、FPS最终ac3dca3、文档29c50dc | 两个代码SHA完整CI均success；被当前呈现/压力分支承接，未合main |
| `codex/demo-playtest-fixes` | 基于main `7def7d2`；简单修复`87262ff`、工具最终`aa4f1a1` | 镜头/外墙与独立缓行诊断分别提交，未合main；两者完整CI通过 |
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
| `main` | 包含最终生产/测试`0856effd4b2bb135c9bae8f25cccbba0e3def8e0`及整合文档 | 唯一集成主线，含通用SL、事件/植物、环境与行动；准确验证分别记录 |
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
