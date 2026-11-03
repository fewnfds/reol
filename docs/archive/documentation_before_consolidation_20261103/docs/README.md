# Reol 文档入口

从[当前状态](BASELINE.md)了解能玩什么，从[开发计划](ROADMAP.md)找到当前任务；[文件架构](PROJECT-STRUCTURE.md)规定内容放在哪里，[代码架构](ARCHITECTURE.md)规定依赖和状态归属。

| 需要了解 | 唯一入口 | 用途 |
|---|---|---|
| 游戏方向 | [GAME-BRIEF](GAME-BRIEF.md) | 愿景、体验、切片范围 |
| 当前完成度 | [BASELINE](BASELINE.md) | 当前构建和验证，不累积历史版本 |
| 接下来做什么 | [ROADMAP](ROADMAP.md) | 顺序；具体工作包放 plans/ |
| 长期开发方案 | [完整游戏方案](plans/full_game_program.md) | 有限1.0、阶段依赖、玩法先行与正式资源时机 |
| 当前实施接续 | [持续Goal](plans/implementation_goal.md) | 共同执行/对练、非人开局、W3-a知物/用器已接，有限自然供给/实际采集已接，当前呈现复查/NPC寄魂/玩家寄魂开局已接，W5-a资格/核验/一次放行已验，用户要求暂停Goal讨论理念；[P0](plans/world_foundation.md)保留未完成性能出口 |
| 整体验收 | [验收矩阵](plans/full_game_acceptance.md) | 从生活到战争/历史的阶段出口，均为未来标准 |
| 最新世界设计 | [世界总纲](../design/systems/self_consistent_world.md)、[世界先行工作包](plans/world_first_sandbox.md) | 多种生命、世界循环、有限认知、器物与创造；W0–W5-a已有有限样本，完整出口仍待做 |
| 世界方案评审 | [整体评审](plans/world_architecture_review.md) | 代码证据、实现难点、12类世界观缺项、3项用户确认与R1–R10未来反例 |
| 基础状态契约 | [W0-a目录](plans/world_state_contracts.md) | 当前状态/单位/ID作用域与接缝；静态梳理完成，未迁移代码 |
| 人物怎样理解世界 | [所见、所知与所在意](../design/systems/perception_and_understanding.md) | 阅历/感知/理解/关注/表达分开；同物异观与防止提示泄密 |
| 同局如何换一生 | [有限转生与新生候选](../design/systems/rebirth_and_new_lives.md) | 世界只前进、跨种族候选、有限次数与终局、防人口筛选；未实现 |
| 人形动作与穿戴细化 | [战斗、修行与纸娃娃](plans/combat_character_design.md) | 本领/衣着/动作分工；槽位/节点/资源为人形原型候选，不是世界通则 |
| 工具与资源调研 | [Goal搜集工作包](plans/resource_tooling_scout.md)、[本机审计](DEVELOPMENT-TOOLS-AUDIT.md) | Skill/MCP实际状态、Godot资源候选、版本许可与接续 |
| 文件放哪里 | [PROJECT-STRUCTURE](PROJECT-STRUCTURE.md) | 目录职责、来源和迁移约定 |
| 代码如何合作 | [ARCHITECTURE](ARCHITECTURE.md) | 已实现模块、数据归属、命令与时间 |
| 为什么这样选 | [DECISIONS](DECISIONS.md) | 有日期和状态的决策记录 |
| 玩法如何运转 | [design/](../design/README.md) | 规则、研究、体验边界 |
| 工具与排错 | [TOOLCHAIN](TOOLCHAIN.md) | 安装、MCP、命令和日志 |
| 实现证据 | [当前代码核对](DEMO-REFACTOR-REPORT.md)、[跨聚落服务](SETTLEMENT-SERVICES-IMPLEMENTATION.md)、[双聚落验证](WORLD-CONTINUITY-IMPLEMENTATION.md) | 已交付行为、测试、限制 |
| 交接 | [HANDOFF](HANDOFF.md) | 短入口，不重复整份设计 |

历史版本放 archive/，截图放 qa/，第三方许可证放 third-party/；这些都不是下一步实施指令。一个事实只保留一个当前负责人：进度在 BASELINE，任务在 plans，规则在 design，参数在 data。

文件移动或文档改名后运行 `python tools/check_structure.py`，检查当前入口、本地链接和运行脚本/测试中的资源路径。代码示例和 archive/ 历史引用不作为现行依赖；场景、资源 UID 和导入另按[测试入口](../tests/README.md)验证。
