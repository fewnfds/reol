# 技术落地总表

核对日期：2026-11-09。依据Git分支祖先、实际装配/调用和准确代码证据；七个领域的当前能力与缺口统一维护于此。名称按[术语与代码映射](../engineering/terminology.md)定位，普通环境成员为`environment_fields`。玩法操作查[FEATURES](features.md)，验证查[BASELINE](baseline.md)，授权与停点查[HANDOFF](handoff.md)。已确认规则是目标约束，不等于所有机制已实现。

## 当前主线与普通入口

| 名称 | 实际情况 |
|---|---|
| Git `main` / `origin/main` | 已快进并推送共同结算集成点`8cc40919599680d57e1f333f1482ebab38df7e3b`，包含共同空间、建筑及此前完整框架；结算最终测试SHA的CI42508829722已核success，精确证据见BASELINE |
| 本轮工具与文档整合 | 官方Actions Node24升级代码`dc2558b`已合入main；架构缺口写回原主计划，不改游戏规则、不启动植物实现，准确验证状态见HANDOFF |
| 普通 `Main` 游戏入口 | `scenes/main.tscn`及其运行接线；有限游戏能力和Git集成状态分别按功能及版本证据核验 |

通用参与索引、环境局部/到期执行、健康活跃集合、共同空间/最小行动和通用建筑均已接普通Main并合入Git main；共同结算内核也已合入main。隔离旧实验`codex/field-contest`与命名stash不是待发布功能或自动恢复任务。来源见[分支页](branches.md)及[建筑验收](../qa/20261108_building_framework.md)。

## 按顶层框架的实际接入

领域职责以[顶层框架](../engineering/architecture/05-framework-domains.md)为准，依赖与出口以[基础建设计划](../plans/foundation-priorities.md)为准。下表均为当前main能力；前两阶段达到声明范围出口，各顶层领域仍有后续扩展边界。

| 顶层框架 | 已有运行能力与主要入口 | 距框架出口的缺口 |
|---|---|---|
| **世界地块与空间框架** | [WorldMapData](../../scripts/sim/world_map_data.gd)、[ReolWorld](../../scripts/world/world.gd)；512²平面、64²显示区块、草/水/岩、稀疏地表改造；[SimWorldObjectQuery](../../scripts/sim/world_object_query.gd)与显式引用空间快照；`SimWorldSpace`组合身体/地面物/结构实时局部查询、冻结变更与恢复重建 | 普通地图规格固定，非任意规模生成；实时查询已覆盖现有身体/地面物/结构，未包含植物/衣物/全部容器；快照仍不枚举全世界；高差/多层后置 |
| **实体、物品与容器框架** | [SimEntityQuery](../../scripts/sim/entity_query.gd)、[SimEmbodiment](../../scripts/sim/embodiment.gd)提供原身体/能力/几何；[SimObjectLifecycle](../../scripts/sim/object_lifecycle.gd)、[SimInventory](../../scripts/sim/inventory_ledger.gd)、[SimGroundPlacements](../../scripts/sim/ground_placements.gd)支持原物生命周期、同账本转移/堆拆/预约；建筑箱已接原库存、数量总容量和过滤 | 植物尚未接共同引用/生命周期；跨账本搬运、普遍体积/负重规则、嵌套容器、独特器物入箱、自由背包与完整处分权限未齐。各原owner分工继续保留，不需要合并成一个对象库 |
| **建筑与组合空间框架** | 第2阶段声明范围已交付；`SimConstruction`持多格/朝向、工地/用途、施工及耐久/损毁；`SimConstructionGeometry`校验定义；`SimStructureQuery`/`SimEnclosedSpace`推导空间；`SimFacilityUse`接操作位/桌椅/真实储藏，原生产接工作台，普通营造入口可用 | 当前限home账本/授权和有界工地；通用维修、更多设施能力、私人地产及跨区政策尚未接。完整工艺归生产，房温/灯火归环境，路径/主动攻击归行动；这些边界不计作已实现建筑能力 |
| **植被与自然生命框架** | [NaturalEnvironment](../../scripts/sim/natural_environment.gd)派生地表覆盖；[SimLandResources](../../scripts/sim/land_resources.gd)持有限资源账和两处野药响应；[SimAvianLife](../../scripts/sim/avian_life.gd)与[SimLargeBodies](../../scripts/sim/large_bodies.gd)提供有限非人生命 | 核心缺口是独立植物身份、位置/占地、可变生命周期及采集/损毁接口，尚未进入共同实时空间和普遍环境接缝；现有覆盖不是植物群体。完整动物繁衍/食物网另属后续，巨兽不可选 |
| **环境框架** | [SimWorldEnvironmentFields](../../scripts/sim/world_environment_fields.gd)作为唯一室外冷热/五行实际响应；真实地面/固定来源、衰减/max、等级抵消、响应建立/消散和残留存读，人体/野药同温度；历法、地理新局编译、有限晴雨、自然日照、固定灯/随身固有微光与遮挡 | 随身物整体发源/尾迹/遮掩、容器透过及树兽墙材普遍发源未接；一房一温、隔热/开敞/拆合连续性未实现；完整雨雪/风/空气与五行后果后续实现，风水仅有规则；五行火不等于发热，光不等于冷热辐射 |
| **单位行动与交互框架** | [SimLocalMotion](../../scripts/sim/local_motion.gd)、[SimRouteTravel](../../scripts/sim/route_travel.gd)、多格扫掠及运行层寻路读原身体/空间；[SimInteractionRequests](../../scripts/sim/interaction_requests.gd)与原执行器区分表达/理解/意愿/耗时/中断/结果，耗时搬运已接普通面板；`SimActionContract`使取放/施工/家具使用共用条件、占用、复核、终态与释放 | 动作仍由各领域过程执行，门面列举20种事项；最小合同已接取放/施工/家具使用，全领域共同生命周期、接近/效果组合和策略入口未齐。动态路径失效/重规划属于本框架内部缺口；固定运粮仍保护原路，非全局动态绕路 |
| **认识与自主决策框架** | [SimSocialMemory](../../scripts/sim/social_memory.gd)私人认识/有向关系/来源、当面自述；[SimInstitutionBook](../../scripts/sim/institution_book.gd)任职公账和贡献；双聚落需求/职责/吃住/采集生产、预约、少量自主目的和互助；迷雾/探索提供有限观察接缝 | 新对象/属性未全面接共同观察与认识；通用目标/策略编排、工作依赖及授权依据仍有限；关系判断仍用有限因素加权/边界骰与逐人值。通用Claim为候选，现有贡献不等于Claim；制度与长程社会玩法后续实现 |

## 阶段整合与基础缺口

共同空间、通用建筑及共同结算在声明范围内已交付。`SimSettlementKernel`/`SimWorldSettlement`提供依赖、同刻顺序和预算游标；普通停止、完整结果/画面发布、FAILED暂停与合法旧档恢复已接普通Main。最终251组/125351检查/0失败及同测试SHA CI通过，原生停开同未来和持续欠算画面已验，详见[QA](../qa/20261108_settlement_kernel.md)。这不表示七领域、全部原子回调或密集长期世界已经完成。

按本轮静态核查，优先补的是现有共同合同的覆盖范围：

- **会话规则来源尚未封闭。** `ReolContentDB.DOCUMENT_PATHS`有39份定义，但不含`local_actions.json`、`workplaces.json`和`sparring.json`；`SimLocalMotion`/`GameClock`/`SimWorkplaces`/`SimSparring`仍读本地规则。更换这些文件后，载入旧世界有混用规则或拒绝在途状态的风险；本轮确认代码路径，未据此声称已运行版本变更复现。`save_game`还只在pending时返回`ERR_BUSY`，尚无自动协调到安全边界再保存的普通入口。下一领域开发先补会话绑定与安全存读合同。
- **对象变化与行动仍是有限共同接入。** `SimWorldSpace`已组合原身体/物品/结构，尚无植物kind；`SimActionContract.describe`只投影取放、施工、家具三个过程owner。植物阶段必须接唯一身份、阶段变化/移除、空间及环境失效、行动预约释放与最小观察；不为此另造万能对象库，也不先迁移全部旧动作。
- **运行预算和长期状态尚无整机出口。** 内核按工作项计数，多数原子回调及地区前置推进不能抢占；库存`operations`、认识`events`等仍可增长。已有阶段/失败诊断，但无声明密集规模的原子耗时、积压、命令/保存等待与多年存档增长证据。沿原owner补有界诊断、联合样本及引用安全保留策略，不能删除幂等/认识依据凑性能。

`NaturalEnvironment`只是地表覆盖，原野药账不是独立植物群体。下一领域仍为植物，先收敛会话规则来源，再以草本/木本检验上述共同合同；后续环境组合→完整行动→共同认识的领域顺序保持。权威查询与个人所知继续隔离，必要观察从植物首次可作用时参与。具体依赖与出口只改[唯一主计划](../plans/foundation-priorities.md)，本轮不启动这些新功能。

## 贯穿框架的运行与工具合同

| 公共能力 | 已有接入 | 未覆盖与验收边界 |
|---|---|---|
| 共同时间、结算与远区 | 已集成的[SimSettlementKernel](../../scripts/sim/execution/settlement_kernel.gd)与[SimWorldSettlement](../../scripts/sim/execution/world_settlement.gd)提供编译依赖、8个阶段、到期边界和预算续算；`GameClock`与[RegionalSimulation](../../scripts/sim/regional_simulation.gd)仍持共同整数毫秒、双聚落离场接续、行旅/货运/消息 | `SimFacilityUse`已按活动项接预算，其余原子回调及领域内部大循环未自动可抢占；非所有领域事件化，大人口、多年与密集动态组合未验。具体受检版本与限制见[QA](../qa/20261108_settlement_kernel.md) |
| 定义、装配与当前快照 | 内容包v2绑定39份定义/开局及digest；[WorldRestoreFactory](../../scripts/sim/world_restore_factory.gd)、[SessionSaveSchema](../../scripts/persistence/session_save_schema.gd)、[SimSaveStore](../../scripts/persistence/save_store.gd)提供联合候选恢复、JSON快照、在途恢复、文件备份/替换和失败不改活世界 | 移动/工作场所/对练等仍有直接读盘规则，普通呈现/恢复限定home、river两区；当前根53，根1–52拒绝；尚未自动暂停→结步→保存→恢复。历史位置/回执尚无长期安全回收，不是事件重放系统 |
| 稀疏执行与规模 | main的[SimParticipationIndex](../../scripts/sim/execution/participation_index.gd)已接环境和健康，member/active/due/dirty及生命周期重建可运行 | 自主、衣物、空间候选、光/UI及历史查询未普遍迁入；定义编译/能力登记未统一覆盖内容。按所属框架的实测收益补接，不能把算法或静态压测视为整机验收 |
| 创作、呈现与诊断 | `--world-editor`的F8地表/真实物编辑，F3诊断、普通面板和代码示意外观，沿原规则与存档 | 完整内容/开局/组合模板编辑和独立预览未齐；开发生成是权限，不是玩家免费造物；正式多体型/全装备和全动作仍未完成 |
| GPU计算 | main历史中有独立CPU/GPU/auto基础场计算服务及旧版对照证据 | 普通响应/原物事务仍为CPU，无玩家GPU开关；隔离加速倍数不等于全游戏收益，联合性能以实际版本/负载为准 |

## 世界内容与玩家能力

| 领域 | main已有的有限组合 | 已定方向中仍未实现 |
|---|---|---|
| NPC与生活 | 双聚落需求、职责、采集/生产/吃住、预约、少数真实目的和当面互助 | 通用人格/长程计划、迁居、多组织经济与海量群像 |
| 社会与认识 | 私人记忆/有向关系/来源、当面自述；[SimInstitutionBook](../../scripts/sim/institution_book.gd)保存任职公账与贡献，另有有限凭据/钱货/通行；关系判断仍用有限因素加权/边界骰与逐人关系值 | 通用Claim是候选，当前贡献记录不等于已实现通用Claim；传闻/礼数/司法政治、自由组织治理和掌门去世继任链未完成，继任纯函数仍隔离 |
| 战斗与身体 | 对练、有限木剑/气弹/护障/闪身、真实体力与灵气、挫伤和经脉不适/救护/恢复 | 完整动作战斗、致死伤亡/尸体/遗物、群战/战争、玩家战斗脚本 |
| 修行与物品认识 | 少数源引息、探查/用法学习、有限试验/手记/传授、本人本领来源目录 | 大型可成长天赋网络、境界突破、自由创法、普遍鉴定/反噬/传承 |
| 衣着与外观 | 实际取放/穿脱、湿润与保暖；代码像素八向分层、解剖左右与附着样例 | 正式多体型/全装备与全动作；奔跑/冲刺/倒地等完整动画；衣饰社交后果 |
| 自然与生命 | 有限自然资源、两处野药、雀生活/玩家雀身、残识/载体、3×3山兽 | 完整植物/动物实体生态、树开局、繁衍/成长/寿命、妖怪组织与超巨体 |
| 人生接续 | 三种开局身份可选，原身体/知识仍分开 | 死亡→消耗机会→新生候选→继续原世界、次数难度与耗尽终局，均未接成玩法 |
| 产品 | 能运行/存读的小世界与多条短体验链、代码示意资源 | 45–60分钟完整切片、正式资源/音效、平衡与试玩、Windows独立包及发布验收 |

上述缺口是既定方向的实现边界，**不是本页生成的新施工队列**。后续框架建设仍查[基础优先级](../plans/foundation-priorities.md)和用户最新授权。

## “运行良好”的证据限度

当前集成的建筑代码d00bac有本机4片完整覆盖250组/126290检查/0失败、3份普通在途档完全停开同未来、一次原生审查发现并修复4项问题，以及同SHA CI42457788038 completed/success。集成点至阶段盘点仅Markdown，不重复引擎/整套回归/模型审查；主线push的新run独立记证据，详情见BASELINE。

不能用前序截图/帧时替代当前版本的规模验收，也不能拿此前26万静态物品的旧版压力结果担保当前密集动态世界。当前没有证据要求换引擎，也没有证据宣称全游戏规模已达标。
