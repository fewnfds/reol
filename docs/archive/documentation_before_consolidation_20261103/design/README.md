# 游戏设计与研究

`systems/` 说明游戏规则和玩家体验，`research/` 保留来源、比较和取舍。当前完成度以[BASELINE](../docs/BASELINE.md)为准；长期步骤见[完整游戏方案](../docs/plans/full_game_program.md)，下一实施包见[世界可靠基础](../docs/plans/world_foundation.md)，代码职责见[ARCHITECTURE](../docs/ARCHITECTURE.md)。

| 当前文档 | 用途 |
|---|---|
| [众生自行其道：世界总纲](systems/self_consistent_world.md) | 最新方向：世界循环、多种生命、跨用途作用与可解释的意外；只设计未实现 |
| [众生与生活方式](systems/beings_and_lifeways.md) | 主体/身体/控制/社会身份分离；凡人、修士、鸟妖、寄魂者、古兽的生活样本 |
| [知物、用器与创法](systems/knowledge_artifacts_and_invention.md) | 有限鉴定、条件使用、反噬、骗经、独立器灵、方法创造与传播 |
| [所见、所知与所在意](systems/perception_and_understanding.md) | 领域阅历、感知/理解、关注与表达；高手和外行看见不同信息，真值不变 |
| [有限重生与新生候选](systems/rebirth_and_new_lives.md) | 不回滚的多世人生、跨种族出生、难度/次数与终局、抽取和防人口筛选 |
| [系统沙盒研究](research/emergent_sandbox_world_references.md) | 八组官方来源、可借鉴机制、证据边界与Reol取舍 |
| [总体框架](systems/living_world_framework.md) | 人物行动、信息、组织与局势如何合作 |
| [完整玩法目标](systems/playable_world_target.md) | 生计、生产/建造、修炼/战斗、社会和多身份；待实现方案 |
| [大世界目标架构](systems/world_simulation_target.md) | 精度/时间/状态交接、经济/战争/人口/历史；待实现契约 |
| [行动战斗](systems/combat_framework.md) | 动作时序、命中/防御、实力来源、指令与共同时间；本轮仅详细设计 |
| [衣着与物品](systems/appearance_and_possessions.md) | 纸娃娃穿戴、物权/用途/社会线索；普通衣饰不堆战斗词条 |
| [修行与学习](systems/cultivation_and_learning.md) | 无职业本领网络、师承/实践、准备/运转、非战斗成长 |
| [世界连续性](systems/world_continuity.md) | 离场、远区推进和归来接续的体验契约 |
| [社会交互评审](systems/social_interaction_review.md) | 用户理念、科学观念与简化取舍 |
| [社会系统旧提案](systems/social_system.md) | Claim 与继任原型；提案状态不等于全局规则已接受 |
| [游戏机制研究](research/social_interaction_game_references.md) | 游戏与研究原型的能力、来源和边界 |
| [项目组织研究](research/project_structure_references.md) | 文件职责选择的参考依据 |
| [完整游戏参考与素材](research/full_game_reference_map.md) | 九组作品取舍、可商用素材候选与代码制作路线 |
| [Godot生态资源候选](research/godot_resource_candidates.md) | 官方库/商店、插件/示例/资源版本许可；非安装清单 |
| [战斗与人物参考](research/combat_and_character_references.md) | Hades/DNF/LoL/WC3/PoE与伪装机制的一手依据、Reol取舍 |

新系统按需要从[模板](systems/_TEMPLATE.md)起草，使用小写 `snake_case` 文件名；没有实际内容时不预建空目录。

规则应说明优先级、适用条件、失败和可观察后果，给出人物或玩家能改变选择的场景。参数说明单位和范围，运行定义进入 `data/`；设计文档不重复维护当前测试数或代替待实施工作包。已有用户授权内的小步实现按工作包推进，无需每次额外确认文档。
