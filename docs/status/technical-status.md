# 技术落地总表

核对日期：2026-11-10。依据Git分支祖先、实际装配/调用和准确代码证据；七个领域的当前能力与缺口统一维护于此。名称按[术语与代码映射](../engineering/terminology.md)定位，普通环境成员为`environment_fields`。玩法操作查[FEATURES](features.md)，验证查[BASELINE](baseline.md)，授权与停点查[HANDOFF](handoff.md)。已确认规则是目标约束，不等于所有机制已实现。

## 当前主线与普通入口

| 名称 | 实际情况 |
|---|---|
| Git `main` / `origin/main` | 当前为`839ff88f1b7fee240d0c798f533314a3ae446430`，含上述框架及后续试玩/缓行/连续呈现和压力Demo；同SHA完整CI通过；精确证据见BASELINE |
| 共同时间流速整合 | 产品/永久测试`f4257e38a1665c08c8596028fe71c0cea0dbeab9`已合入main，CI42542611182完整通过；有限准入、自动降速、宿主步骤预算和HUD/F3已接普通Main，后续仅QA驱动与文档，准确证据见BASELINE |
| 通用存读工作分支 | `codex/save-load-framework`主体96a6fe0、最终代码d682e03已推送，已随行动历史合入main；下文能力在主线可用，完整CI状态见[QA](../qa/20261109_save_framework.md) |
| 事件与植物工作分支 | `codex/world-events-plants` 承接SL；全局事件/规则闭包、植物实例、环境/空间/行动和花盆已接普通Main并推送；原生主审/修复及停开完成；13d675e对应12片CI完整256组通过，已随行动历史合入main |
| 环境组合工作分支 | `codex/environment-composition`承接上述历史；补材质传播、单一房温、容器/携物与植物照明，已随行动历史合入main；主线整合CI通过 |
| 完整行动工作分支 | `codex/unit-actions-integration`承接上述历史；共同投影/终态/停止、原生搜索与受阻重评、原库存跨账本搬运、普通面板及有限战斗衔接已实现；已合入main，主线整合CI通过 |
| 普通 `Main` 游戏入口 | `scenes/main.tscn`及其运行接线；有限游戏能力和Git集成状态分别按功能及版本证据核验 |

通用参与索引、环境局部/到期执行、健康活跃集合、共同空间/最小行动和通用建筑均已接普通Main并合入Git main；共同结算内核及共同时间负载调速均已合入main。隔离旧实验`codex/field-contest`与命名stash不是待发布功能或自动恢复任务。来源见[分支页](branches.md)及[建筑验收](../qa/20261108_building_framework.md)。

## 按顶层框架的实际接入

领域职责以[顶层框架](../engineering/architecture/05-framework-domains.md)为准，依赖与出口以[基础建设计划](../plans/foundation-priorities.md)为准。下表含当前main的事件/植物、环境与行动代码（主线整合CI通过）；主线集成与准确验证以HANDOFF/BASELINE为准。前三阶段达到声明范围出口，各顶层领域仍有后续扩展边界。

| 顶层框架 | 已有运行能力与主要入口 | 距框架出口的缺口 |
|---|---|---|
| **世界地块与空间框架** | [WorldMapData](../../scripts/sim/world_map_data.gd)、[ReolWorld](../../scripts/world/world.gd)；512²平面、64²显示区块、草/水/岩、稀疏地表改造；[SimWorldObjectQuery](../../scripts/sim/world_object_query.gd)与显式引用空间快照；`SimWorldSpace`组合身体/地面物/结构实时局部查询、冻结变更与恢复重建 | 普通地图规格固定，非任意规模生成；实时查询已覆盖现有身体/地面物/结构，植物已接入主线；衣物/全部容器尚未覆盖；快照仍不枚举全世界；高差/多层后置 |
| **实体、物品与容器框架** | [SimEntityQuery](../../scripts/sim/entity_query.gd)、[SimEmbodiment](../../scripts/sim/embodiment.gd)提供原身体/能力/几何；[SimObjectLifecycle](../../scripts/sim/object_lifecycle.gd)、[SimInventory](../../scripts/sim/inventory_ledger.gd)、[SimGroundPlacements](../../scripts/sim/ground_placements.gd)支持原物生命周期、同账本转移/堆拆/预约；建筑箱已接原库存、数量总容量和过滤 | 植物已接共同引用/原生命过程；原services已接数量物跨账本搬运；普遍体积/负重规则、嵌套容器、独特器物入箱、自由背包与完整处分权限未齐。各原owner分工继续保留，不需要合并成一个对象库 |
| **建筑与组合空间框架** | 第2阶段声明范围已交付；`SimConstruction`持多格/朝向、工地/用途、施工及耐久/损毁；`SimConstructionGeometry`校验定义；`SimStructureQuery`/`SimEnclosedSpace`推导空间；`SimFacilityUse`接操作位/桌椅/真实储藏，原生产接工作台，普通营造入口可用 | 当前限home账本/授权和有界工地；通用维修、更多设施能力、私人地产及跨区政策尚未接。完整工艺归生产，房温/灯火归环境，路径/主动攻击归行动；这些边界不计作已实现建筑能力 |
| **植被与自然生命框架** | [SimPlants](../../scripts/sim/plants.gd)持原株、生境/物候/寿命/残株、采集/损毁/花盆和最小植灵；`NaturalEnvironment`持地表背景，`SimLandResources`保留原产物账；`SimAvianLife`与`SimLargeBodies`提供有限非人生命 | 任意距离活株搬运、全域自然种群生成/繁衍、生态网与完整树身人生仍未接。完整动物繁衍/食物网另属后续，巨兽不可选 |
| **环境框架** | 原温度/五行响应、共享气候背景与参与索引；主线已扩展`SimEnvironmentLayout`的材质传播/房间成员、同房温度锚点、箱体/携物/库存来源和植物人工光，主线整合CI通过 | 充分混合、射线与tau是近似；无空气流体/热守恒、任意嵌套、鸟兽本体/人物体质整体源、完整风水玩法或密集规模出口。`context_at`仅为authority_only实际布局/环境查询 |
| **单位行动与交互框架** | [SimLocalMotion](../../scripts/sim/local_motion.gd)、[SimRouteTravel](../../scripts/sim/route_travel.gd)、多格扫掠及运行层寻路读原身体/空间；[SimInteractionRequests](../../scripts/sim/interaction_requests.gd)与原执行器区分表达/理解/意愿/耗时/中断/结果，耗时搬运已接普通面板；`SimActionContract`使取放/施工/家具使用共用条件、占用、复核、终态与释放 | 原过程共用只读投影、终态及停止入口；`SimGridNavigation`复用AStar2D，`SimRouteTravel`按共同边界重评；原services搬运支持不同容器/账本、保管与设施容量，工作可交给有限战斗。尚无任意全局规划、全部飞行/穿墙能力、嵌套/普遍负重、完整战斗或通用策略；证据行旅/规定步法保留原遇阻中断规则 |
| **认识与自主决策框架** | [SimSocialMemory](../../scripts/sim/social_memory.gd)私人认识/有向关系/来源、当面自述；[SimInstitutionBook](../../scripts/sim/institution_book.gd)任职公账和贡献；双聚落需求/职责/吃住/采集生产、预约、少量自主目的和互助；迷雾/探索提供有限观察接缝 | 新对象/属性未全面接共同观察与认识；通用目标/策略编排、工作依赖及授权依据仍有限；关系判断仍用有限因素加权/边界骰与逐人值。通用Claim为候选，现有贡献不等于Claim；制度与长程社会玩法后续实现 |

## 阶段整合与基础缺口

共同空间、通用建筑及共同结算在声明范围内已交付。`SimSettlementKernel`/`SimWorldSettlement`提供依赖、同刻顺序和预算游标；普通停止、完整结果/画面发布、FAILED暂停与合法旧档恢复已接普通Main。最终251组/125351检查/0失败及同测试SHA CI通过，原生停开同未来和持续欠算画面已验，详见[QA](../qa/20261108_settlement_kernel.md)。这不表示七领域、全部原子回调或密集长期世界已经完成。

事件/植物阶段已在声明范围内完成，最终CI与证据见BASELINE：

- **规则闭包与全局事件已在工作分支补齐。** 内容包3有44份定义/开局，移动、值事房、约练按会话绑定；`SimEventQueue`接定时/周期/条件唤醒和幂等回执，`SimWorldEvents`首先服务运输与植物。最终准确证据仍看BASELINE；这不等于全部玩法触发已迁入。
- **对象变化与行动保持原owner。** `SimWorldSpace`组合原身体/物品/结构/植物，`SimActionContract.describe`投影取放、施工、家具和植物过程。植物变化更新空间/来源、复核行动和释放预约；普通观察守可见范围。原库存搬运和现有行动共同投影在第5阶段接入，共同认识仍后置。
- **运行预算和长期状态尚无整机出口。** 共同时间已补有限准入、宿主成本反馈与6ms合作式步骤预算，详见[合同](../engineering/simulation-pacing.md)；多数原子回调及地区前置推进仍不能抢占；库存`operations`、认识`events`等仍可增长。已有阶段/失败诊断，但无声明密集规模的原子耗时、积压、命令/保存等待与多年存档增长证据。沿原owner补有界诊断、联合样本及引用安全保留策略，不能删除幂等/认识依据凑性能。

`NaturalEnvironment`持地表背景；植物型资源在开局交接给`SimPlants`，产物保留原库存，旧增长停用。当前整合完整行动，下一顶层领域为共同认识；用户希望先尽快试玩，后续范围仍按最新授权。权威查询与个人所知继续隔离；具体依赖与出口只在[唯一主计划](../plans/foundation-priorities.md)维护，后续领域不因本轮研究自动开工。

## 贯穿框架的运行与工具合同

| 公共能力 | 已有接入 | 未覆盖与验收边界 |
|---|---|---|
| 共同时间、结算与远区 | 已集成的[SimSettlementKernel](../../scripts/sim/execution/settlement_kernel.gd)与[SimWorldSettlement](../../scripts/sim/execution/world_settlement.gd)提供编译依赖、9个阶段、到期边界和预算续算；`GameClock`与[RegionalSimulation](../../scripts/sim/regional_simulation.gd)仍持共同整数毫秒、双聚落离场接续、行旅/货运/消息 | `SimFacilityUse`、植物到期及离散事件已按实际工作接预算，其余原子回调及领域内部大循环未自动可抢占；非所有领域事件化，大人口、多年与密集动态组合未验。具体受检版本与限制见[QA](../qa/20261108_settlement_kernel.md) |
| 定义、装配与当前快照 | 主线内容包v3绑定44份定义/开局及digest；[WorldRestoreFactory](../../scripts/sim/world_restore_factory.gd)、[SessionSaveSchema](../../scripts/persistence/session_save_schema.gd)、[SimSaveStore](../../scripts/persistence/save_store.gd)与`SimSaveRegistry`/`SimWorldSaveDomains`/`SimSaveSession`提供统一领域管线、安全保存请求与回执、联合候选恢复及文件备份/替换 | 移动/工作场所/对练使用会话规则，普通呈现/恢复限定home、river两区；当前根56/区域47，仅接受当前格式，旧档明确拒绝；保存屏障停止新时间、结清受理工作并保留暂停状态。历史位置/回执尚无长期安全回收，不是事件重放系统 |
| 稀疏执行与规模 | main的[SimParticipationIndex](../../scripts/sim/execution/participation_index.gd)已接环境/健康与原行动截止堆；工作分支扩显式身体同步/纯查询、到期及失效人物筛选、领域工作条件 | 尚有活动域内部轮询、完整世界边界、公共发布同步和重复布局；空间候选、光/UI及历史查询未普遍稀疏化。100/300人原生约0.970/0.430×，规模出口未达，准确范围见共同运行QA |
| 创作、呈现与诊断 | `--world-editor`的F8地表/真实物编辑，F3诊断、普通面板和代码示意外观，沿原规则与存档 | 完整内容/开局/组合模板编辑和独立预览未齐；开发生成是权限，不是玩家免费造物；正式多体型/全装备和全动作仍未完成 |
| GPU计算 | main历史中有独立CPU/GPU/auto基础场计算服务及旧版对照证据 | 普通响应/原物事务仍为CPU，无玩家GPU开关；隔离加速倍数不等于全游戏收益，联合性能以实际版本/负载为准 |

## 世界内容与玩家能力

| 领域 | 当前工作分支的有限组合 | 已定方向中仍未实现 |
|---|---|---|
| NPC与生活 | 双聚落需求、职责、采集/生产/吃住、预约、少数真实目的和当面互助 | 通用人格/长程计划、迁居、多组织经济与海量群像 |
| 社会与认识 | 私人记忆/有向关系/来源、当面自述；[SimInstitutionBook](../../scripts/sim/institution_book.gd)保存任职公账与贡献，另有有限凭据/钱货/通行；关系判断仍用有限因素加权/边界骰与逐人关系值 | 通用Claim是候选，当前贡献记录不等于已实现通用Claim；传闻/礼数/司法政治、自由组织治理和掌门去世继任链未完成，继任纯函数仍隔离 |
| 战斗与身体 | 对练、有限木剑/气弹/护障/闪身、真实体力与灵气、挫伤和经脉不适/救护/恢复 | 完整动作战斗、致死伤亡/尸体/遗物、群战/战争、玩家战斗脚本 |
| 修行与物品认识 | 少数源引息、探查/用法学习、有限试验/手记/传授、本人本领来源目录 | 大型可成长天赋网络、境界突破、自由创法、普遍鉴定/反噬/传承 |
| 衣着与外观 | 实际取放/穿脱、湿润与保暖；代码像素八向分层、解剖左右与附着样例 | 正式多体型/全装备与全动作；奔跑/冲刺/倒地等完整动画；衣饰社交后果 |
| 自然与生命 | 原植物实例/生境/寿命/残株、花盆、最小植灵；雀生活/玩家雀身、残识/载体、3×3山兽 | 全域种群生成/繁衍/食物网、完整动物成长/寿命、妖怪组织与超巨体 |
| 人生接续 | 三种开局身份可选，原身体/知识仍分开 | 死亡→消耗机会→新生候选→继续原世界、次数难度与耗尽终局，均未接成玩法 |
| 产品 | 能运行/存读的小世界与多条短体验链、代码示意资源 | 45–60分钟完整切片、正式资源/音效、平衡与试玩、Windows独立包及发布验收 |

上述缺口是既定方向的实现边界，**不是本页生成的新施工队列**。后续框架建设仍查[基础优先级](../plans/foundation-priorities.md)和用户最新授权。

## “运行良好”的证据限度

当前集成的建筑代码d00bac有本机4片完整覆盖250组/126290检查/0失败、3份普通在途档完全停开同未来、一次原生审查发现并修复4项问题，以及同SHA CI42457788038 completed/success。集成点至阶段盘点仅Markdown，不重复引擎/整套回归/模型审查；主线push的新run独立记证据，详情见BASELINE。

主线提供连续显示及真实巡行压力入口。共同运行包落实显式同步和稀疏筛选，最终快照与旧版一致；耗时有反向样本，未证明稳定提速，严重缓行仍未解决。[CPU根因调查](../qa/20261110_runtime_cpu_root_cause.md)实测模拟集中一条线程，寻路内84.81%通行查询重复；普通模拟没有多核任务或GPU计算接入。[共同运行QA](../qa/20261110_sparse_runtime_dispatch.md)保留主审/原生/停开证据；仍沿原计划改共同运行、导航及呈现规模。

不能用前序截图/帧时替代当前版本的规模验收，也不能拿此前26万静态物品的旧版压力结果担保当前密集动态世界。当前没有证据要求换引擎，也没有证据宣称全游戏规模已达标。
