# 游戏设计与研究

本文是**设计入口与领域路由**。实际可玩功能见[FEATURES](../docs/status/features.md)，当前构建与证据见[BASELINE](../docs/status/baseline.md)，任务停点与授权见[HANDOFF](../docs/status/handoff.md)。规则、未来测试编号和参考研究都不表示已实现或已验收。

## 如何使用本目录

1. 先看[游戏愿景](vision.md)、[世界总纲](systems/self_consistent_world.md)与用户最新指令；目标、已拍板概念和开发建议分别理解，不把具体参数或示例升级成用户决定。
2. 按下表选择需要的领域；跨领域用[世界与交互原则](systems/world_interaction_principles.md)衔接。实施顺序看[世界引擎总计划](../docs/specs/world-engine/program.md)和[执行计划](../docs/archive/specifications/world_engine_execution.md)，但是否执行仍以用户最新指令与HANDOFF为准。
3. 当前行为查FEATURES、实现归属查[ARCHITECTURE](../docs/engineering/architecture.md)、已验证版本和证据查BASELINE。设计页中成文时的“当前”和当时的验收属于历史快照；工作树的未验收代码也不能写成已验收基线。
4. 研究只提供来源和取舍，旧方案/旧ADR标明提案时不能当现行决定；同一规则出现不同表述时，以用户较新明确决定、现行领域契约和可核验代码为准，并区分目标与现状。

[超凡者优先](../docs/archive/specifications/transcendent_focus.md)明确战斗/装备/功法/学习/冒险/组织与事件化远区的开发重心，普通生产先维持基础循环；首轮新世界采用平面地块，高低差研究暂缓。两项均不意味着已经实现相关完整玩法。

## 共同理念与领域规则

| 文档 | 负责什么 | 当前实现关系 |
|---|---|---|
| [世界总纲](systems/self_consistent_world.md) | 众生自行其道、跨用途作用、循环、自洽与开放选择 | 方向；有局部样本，非完整世界实现 |
| [世界与交互原则](systems/world_interaction_principles.md) | 环境/五行/风水/建筑/组织/策略与AI兜底原则 | 长期方向；局部样本见FEATURES |
| [众生与生活方式](systems/beings_and_lifeways.md) | 主体、身体、控制、身份与不同生命的可玩处境 | 有人/鸟/魂短样本；树/古兽等待做 |
| [知物、用器与创法](systems/knowledge_artifacts_and_invention.md) | 有限认识、条件使用、反噬、欺骗、独立器灵、创造/传播 | 温石/寄魂/口头资格有专用样本；通用机制待做 |
| [人物视角](systems/perception_and_understanding.md) | 感知、领域理解、关注、表达及提示防泄密 | 有个人认识投影，非完整信念系统 |
| [有限转生](systems/rebirth_and_new_lives.md) | 世界不回滚、跨种族新生候选、有限次数/终局、防人口筛选 | 设计待实现；开局选择不等于转生 |
| [总体框架](systems/living_world_framework.md) | 人物行动、信息、组织与局势怎样合作 | 首骨架已接；旧起点、参数与开发顺序为历史 |
| [世界连续性](systems/world_continuity.md) | 离场、远区推进与归来接续契约 | 当前双聚落已有实现，扩大仍待验 |
| [跨聚落服务](systems/settlement_services.md) | 吃住、运粮、凭据、机构办理与条件互助 | 有限闭环已接 |
| [建造与空间](systems/construction_and_space.md) | 空间/区域/家具/容器/人物组合；起居、各类工序、知识与实物储藏、装饰/呈现、迁建/破坏和近远连续性 | 门墙/床位/有限屋面和固定值事房已有样本；通用房间/设施/储藏规则为设计待实现 |
| [社会交互评审](systems/social_interaction_review.md) | 用户理念、科学观念与游戏化简化 | 决策依据，不宣称完整心理模拟 |
| [社会关系与机构记录](systems/social_system.md) | 个人关系、组织、记录及继任的边界 | 记账有样本；Claim及继任算法为待评审候选，旧全文归档 |
| [行动战斗](systems/combat_framework.md) | 动作、实力来源、指令与共同时间 | 山门对练样本已接，完整战斗待做 |
| [衣着与物品](systems/appearance_and_possessions.md) | 穿搭、用途、产权、社会线索 | 完整纸娃娃/物权待实现，少量器物另有样本 |
| [修行与学习](systems/cultivation_and_learning.md) | 无职业本领网络、师承/实践与创造 | 有限学习、能力展示及指导已有样本；通用网络/突破/创法待做 |
| [完整玩法目标](systems/playable_world_target.md) | 生计/经营/成长/社会的长期出口 | 目标设计 |
| [大世界目标](systems/world_simulation_target.md) | 精度、经济、战争、人口与历史 | 目标契约，非当前规模证明 |

全部当前理念的简明汇总在[GAME-BRIEF](vision.md)，用户确认与开发建议的来源见[DECISIONS](../docs/decisions/README.md)。具体动作/数值/布局仍须原型验证，不把人形资源或槽位变成所有生命的世界法则。

## 研究与来源

| 资料 | 用途 |
|---|---|
| [涌现沙盒研究](research/emergent_sandbox_world_references.md) | 八组官方来源、可借鉴机制与证据边界 |
| [社会交互游戏研究](research/social_interaction_game_references.md) | 游戏和研究原型的做法、限制与Reol取舍 |
| [战斗与人物参考](research/combat_and_character_references.md) | Hades/DNF/LoL/WC3/PoE等一手依据 |
| [完整参考与素材图](research/full_game_reference_map.md) | 更多作品、可商用资源候选与代码制作路线 |
| [Godot生态候选](research/godot_resource_candidates.md) | 官方库/商店、插件/示例/素材的版本与许可；非安装清单 |
| [八方向外观与免费工具](research/eight_direction_sources.md) | Godot原生/FLARE逐方向层序、LPC四向限制、离线八向生产与逐件许可；[实施合同](../docs/specs/presentation/eight-directions.md) |
| [环境、空间与移动源参考](research/environment_sources.md) | 缺氧/饥荒/环世界/修仙模拟器；官方和社区证据分级，产权/容器/已释放场、房间改建与产源/聚流的边界 |
| [自然地块与组合场所参考](research/natural_world_workplace_sources.md) | 环世界/修仙模拟器的生境、房间、温度与五行；说明官方/社区证据边界与本包取舍 |
| [世界引擎研究](research/world_engine_references.md) | 环境数值方法、空间传播、内容与编辑工具的理论和官方资料；不代表对应机制已实现 |
| [高低差与世界拓扑研究](research/elevation_and_world_topology.md) | 地表高度、特殊多层与世界拓扑的案例和取舍；当前平面优先，本研究暂不作为实施前置 |
| [项目组织研究](research/project_structure_references.md) | 目录职责选择的参考 |

`systems/`写规则/优先级/适用条件/失败与可观察后果；`research/`写来源与取舍；`docs/plans/`写实施和验收；`data/`保存真正运行的定义参数。新系统按需要用[模板](systems/_TEMPLATE.md)，不预建空模块。旧工作包/QA保留历史，不自动成为当前任务。
