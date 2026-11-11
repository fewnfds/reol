# 游戏设计与研究

[愿景](vision.md)与[已确认规则](rules/README.md)定义游戏方向；详细机制、参数及例子是候选。实施问题/范围只有[重构主计划](../docs/plans/foundation-priorities.md)一处，不从研究和旧样本恢复任务。

## 设计入口

| 主题 | 入口 |
|---|---|
| 持续世界与共同后果 | [持续世界目标](systems/world_simulation_target.md) |
| 空间、建筑和生活设施 | [建造与空间](systems/construction_and_space.md) |
| 身体、多生命与人生 | [众生](systems/beings_and_lifeways.md)、[有限转生](systems/rebirth_and_new_lives.md) |
| 认识、器物与学习 | [人物理解](systems/perception_and_understanding.md)、[器物与创造](systems/knowledge_artifacts_and_invention.md)、[修行](systems/cultivation_and_learning.md) |
| 社会、交互与组织 | [社会系统](systems/social_system.md)、[有限服务](systems/settlement_services.md) |
| 动作、外观与物品 | [战斗](systems/combat_framework.md)、[衣着与持物](systems/appearance_and_possessions.md) |
| 环境与后置空间候选 | [环境](proposals/environment.md)、[高低差](proposals/elevation.md) |

候选中的旧class、阶段、具体清单和数值均不约束重构；需要采用时先对应当前需求与规则，避免把示例当成必须逐个建设的任务。

## 参考来源

- 架构/执行：[模拟游戏结构](research/colony_sim_architecture.md)、[大型模拟优化](research/large_simulation_optimization.md)、[事件](research/simulation_events.md)。当前采用的执行取舍集中在[计算接入](../docs/engineering/execution-batches.md)。
- 空间/自然：[空间模型](research/spatial_models.md)、[体型净空](research/unit_footprint_and_clearance.md)、[自然与场所](research/natural_world_workplace_sources.md)、[环境来源](research/environment_sources.md)、[世界生成](research/world_engine_references.md)。
- 玩法/资源：[社会研究](research/social_interaction_game_references.md)、[战斗](research/combat_and_character_references.md)、[资源候选](research/godot_resource_candidates.md)、[八方向](research/eight_direction_sources.md)。

研究保留来源日期与证据限制；作品机制不证明其内部实现，公开代码/插件不等于已采用依赖。其余来源通过[记忆地图](../docs/README.md)按需找，不把它们当当前架构或实施队列。
