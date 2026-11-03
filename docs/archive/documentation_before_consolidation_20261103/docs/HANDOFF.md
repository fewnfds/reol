# Reol 快速交接

> **当前授权（2026-11-03）**：用户已要求使用持续Goal实现游戏并自行处理常规问题，覆盖下文此前“仅设计”的阶段限制。实施接续见[当前Goal工作包](plans/implementation_goal.md)，真实完成与证据仍以BASELINE为准；不得将完整游戏Goal提前标为完成。

> **最新实现**：根schema14/区域11/村落3/器物3/寄魂2/临时放行1，真实v1–v14迁移/回归；共同毫秒生活/路线、动作对练、温火石做饭/烘药与NPC本人摸索已有运行证据。两聚落实际雀妖NPC自主觅食/歇翅，B可投食/求衔药，药枝从石隙经鸟嘴进入原药圃；真实v8携药返程档完整重启后相同未来。见[精度](qa/20261103_continuous_life.md)、[对练](qa/20261103_sparring.md)、[器物办法](qa/20261103_heat_methods.md)、[非人生活](qa/20261103_avian_life.md)。新开局可选杂役或雀妖，原身体飞行/觅食/取放药、对应视野和人类NPC自主已接，真实v9重启接续；知物/用器W3-a已接材料与操纵阅历差异、请人检查和强注裂损，见[证据](qa/20261103_artifact_understanding.md)；辨材/强注中途完整重启散列667070107/206336746。有限自然来源与实际采集/NPC补给已接，三日低库存和真实v11重启通过，见[证据](qa/20261103_renewable_livelihood.md)。当前小世界P0呈现等待已定位，项目VSync关/上限120，不改全局；[证据](qa/20261103_presentation_timing.md)。W4-a实际旧戒/独立老人、逐人约定/拒绝、耗时耗费的亲手指导与接手同意已接，见[实际证据](qa/20261103_soul_vessels.md)。W4-b玩家寄魂开局/有限灵机/实际携戒/休眠已交付，见[实际证据](qa/20261103_soul_player.md)，W5-a有限口头资格/核验回执/一次真实取药已交付，见[证据](qa/20261103_social_admission.md)；用户要求本包后暂停Goal，先谈理念；不能免费运行中换身；真实伤亡、长期再生产和完整游戏仍未完成，用户已要求暂停Goal；未完成、待用户恢复实施。

以下条目保留设计/交接过程；其中旧“仅设计”“W0未实施”等以最新实现和BASELINE为准。当前run82暂停444100ms，真实取药已交付、管事核验后回执已给石头看；原行囊药1、贡献0/无正式通行；user://qa_forage_work_active.json是58267ms采集中途。真实v1–v14及overload_v10不可重写；v11重启联合散列1730311216，v12指导中途再100000ms散列1763851330。

1. 读根目录 AGENTS.md，再读[当前状态](BASELINE.md)、[文件架构](PROJECT-STRUCTURE.md)、[完整游戏方案](plans/full_game_program.md)。
2. 用户目标：人物、关系、组织与信息持续运转，玩家是一员；尊敬、信任、实际帮助和制度权利分开。贡献归机构账本。百年闭关只是说明时间变化的例子。
3. 已有双聚落连续性；[实现与边界](WORLD-CONTINUITY-IMPLEMENTATION.md)。当前验证数字仅以 BASELINE 为准。
4. 文件整理、跨聚落办事互助和Demo质量重构已完成；[当前代码核对](DEMO-REFACTOR-REPORT.md)。联合快照候选验证在runtime/world_session_snapshot；数据文件读写仍在persistence。不要重做已完成工作。
5. 保留已有未提交修改；不要重做 contribution/reputation 删除、迁移 MCP 或 M1。不要改 addons/。
6. `python tools/godot.py doctor`、`check`；可见行为须实际运行、读日志、截图。数据模拟使用稳定 ID 和固定世界时间，远近切换不能初始化人物。
7. 最新用户要求完整游戏长期路线＋更多免费可用资源/Skill/MCP/插件研究，已建立Goal；本轮只完成方案/调研，未实施新玩法。详细交付、状态和来源见[Goal接续记录](plans/resource_tooling_scout.md)。
8. 后续先P0相关契约/测量，再按最新[世界先行W0–W7](plans/world_first_sandbox.md)验证多种生命和组合交互，之后扩大长期P1–P8玩法；不必先完成全建造/全战斗才检验非人主体。下一基础包[世界可靠基础](plans/world_foundation.md)，未来验收见[矩阵](plans/full_game_acceptance.md)。三出身/三境界/人口与时长是推荐默认，不冒充用户逐项已定。
9. 37项项目技能与主要游戏MCP已只读复核；[工具审计](DEVELOPMENT-TOOLS-AUDIT.md)含配置归属与真实缺口。[Godot候选](../design/research/godot_resource_candidates.md)与[素材研究](../design/research/full_game_reference_map.md)不是安装清单，不修改addons或全局配置。
10. 最新人物/战斗要求：动作战斗取Hades/DNF/LoL/WC3之长；装备主要纸娃娃换装及社交表达，非人人战士；成长取PoE共享网络但没有固定职业，靠选择、学习/实践。用户明确本轮**仅详细设计，不改游戏代码**；入口[战斗、修行与纸娃娃](plans/combat_character_design.md)，规则分在combat_framework、appearance_and_possessions、cultivation_and_learning；节点/槽位/时序仍是提案，不算实现。

11. 最新世界方向与设计：[众生自行其道](../design/systems/self_consistent_world.md)，配套beings_and_lifeways、knowledge_artifacts_and_invention及八组一手沙盒参考。用户要不同生命/目标在同一世界成立，允许不平衡；《骗经》、未知/难用的宝物、反噬、戒中老人、创法、鸟妖、古兽都有规则与未来测试。固定面板、六衣位、四招/心神、40节点仅原型默认；不再把“一人一身体一背包”当通用不变量。本轮只改设计，W0尚未实施；AIRP是开放设计视角，不等于已接语言模型或支持任意文本执行。

12. 最新[整体评审](plans/world_architecture_review.md)指出真实待补契约：共同时间/打断、主体/载体与空间、错误/冲突认识、作用语义、共同过程、NPC有限方法选择、实例物品与长局再生产。用户已确认单角色死亡/退隐后续接原世界、术法真实改变不同地区社会、日常＋可打断主动快进；见ADR-0030。W0先拆状态/单位目录，W3前补认识命题；不把账实守恒误作禁止造物/分魂。本轮仅文档评审，R1–R10未运行。

13. 2026-11-03：[人物视角](../design/systems/perception_and_understanding.md)区分真值/信号/领域理解/关注/表达，不能用展开、排序、报价与拒绝理由泄密。用户负责概念/全局，开发处理算法/平衡/测试参数。W0-a首轮[状态目录](plans/world_state_contracts.md)已完成静态核对，W0-b/字段迁移未实施；不要把旧“W0尚未开始”的历史表述当当前进度。
14. 2026-11-03用户确认：多数生命有适合自身的修行路径、少数需改变先天条件；普通死亡通常魂散。最新[有限转生](../design/systems/rebirth_and_new_lives.md)与ADR-0033确定：世界不回滚、可小幅前跳，从人/动物/妖类新生候选中接续；次数随难度升高减少，耗尽结束本局，暂不设计增加渠道。取代ADR-0030免费换人和ADR-0032待确认时间的部分。候选先定有限档位/范围再匹配真实出生，不能在幸存者中归一升档；锁世次/批次与独立随机，不用可被杀人数量改变的事件ID摇种子。L1–L12未实现，解析概率示例不当防利用验证；普通存读/铁人未另授权，不暗设跨档扣次。

[原交接全文](archive/handoff_before_structure_20261102.md)仅作历史。
