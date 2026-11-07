# 游戏设计与研究

这里按权威和用途组织游戏设计。游戏愿景见[愿景](vision.md)，用户已确认的世界法则见[规则](rules/README.md)。机制、例子、参数和规模仍可能由设计或原型调整。

## 如何使用本目录

1. 从愿景与已确认规则了解共同方向。用户较新的明确决定优先于旧提案。
2. 从领域设计和提案查机制、条件、失败后果和场景；其中的参数、样本与算法是候选，不因引用而成为用户决定。
3. 研究记录来源、可借鉴之处及其限制；外部作品、资源与插件不自动成为项目承诺或依赖。

中文游戏概念与实际代码标识符的对应见[术语与代码映射](../docs/engineering/terminology.md)。

当前可玩范围与证据见[功能](../docs/status/features.md)和[基线](../docs/status/baseline.md)，当前任务见[接续](../docs/status/handoff.md)，工程归属见[架构](../docs/engineering/architecture.md)，未来工作建议见[计划](../docs/plans/README.md)。重构前原文与旧队列可在[历史快照](../docs/archive/design-context-20261105/README.md)查阅。

## 共同理念与领域规则

| 主题 | 详细设计与候选 |
|---|---|
| 世界与交互 | [世界总纲](systems/self_consistent_world.md)、[世界与交互原则](systems/world_interaction_principles.md)、[持续模拟](systems/world_simulation_target.md)、[世界连续性](systems/world_continuity.md) |
| 生命与成长 | [众生与生活方式](systems/beings_and_lifeways.md)、[修行与学习](systems/cultivation_and_learning.md)、[有限转生](systems/rebirth_and_new_lives.md) |
| 认识与社会 | [知物、用器与创法](systems/knowledge_artifacts_and_invention.md)、[人物视角](systems/perception_and_understanding.md)、[社会交互评审](systems/social_interaction_review.md)、[社会系统](systems/social_system.md)、[总体框架](systems/living_world_framework.md)、[跨聚落服务](systems/settlement_services.md) |
| 生活与冲突 | [建造与空间](systems/construction_and_space.md)、[衣着与物品](systems/appearance_and_possessions.md)、[行动战斗](systems/combat_framework.md)、[完整玩法目标](systems/playable_world_target.md) |
| 专题方案 | [环境](proposals/environment.md)、[战斗与人物](proposals/combat-and-characters.md)、[高低差研究方案](proposals/elevation.md) |

## 研究与来源

| 研究 | 用途 |
|---|---|
| [涌现沙盒](research/emergent_sandbox_world_references.md)、[社会交互](research/social_interaction_game_references.md) | 自主生活、社会事实与信息传播的参考和证据边界 |
| [战斗与人物](research/combat_and_character_references.md)、[完整参考与素材](research/full_game_reference_map.md) | 动作、能力、素材及代码生成参考 |
| [Godot 资源候选](research/godot_resource_candidates.md)、[八方向与免费工具](research/eight_direction_sources.md) | 工具、版本、许可及资源生产的候选调查 |
| [环境来源](research/environment_sources.md)、[自然地块和场所](research/natural_world_workplace_sources.md)、[世界引擎](research/world_engine_references.md)、[高低差和拓扑](research/elevation_and_world_topology.md) | 环境、空间、模拟方法与边界 |
| [格子、体型与巨型单位](research/unit_footprint_and_clearance.md) | 定位锚点/占地/视觉的区分，成熟项目净空方案与破坏开路候选；不等于当前战斗已实现 |
| [方格世界的空间模型](research/spatial_models.md) | Factorio、OpenRA等的逻辑位置、占地、插值及证据边界；单位运动与环境采样分别选型 |
| [大型建造与模拟优化](research/large_simulation_optimization.md) | Factorio、CDDA、Mindustry、OpenTTD的缓存/数据/存读方法；对环境初建与大档热点的适用边界 |
| [超凡者方向](research/transcendent_focus_sources.md)、[项目组织](research/project_structure_references.md)、[项目参考](research/project-references.md) | 内容侧重、目录职责与相关资料 |

新领域可从[模板](systems/_TEMPLATE.md)开始，不预建空模块。
