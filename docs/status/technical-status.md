# 技术落地总表

核对日期：2026-11-08。依据Git分支差异、实际装配/调用和对应版本证据；名称按[术语与代码映射](../engineering/terminology.md)定位。当前普通环境成员为`environment_fields`，存档键由codec映射保持；建筑包接入范围与main集成状态分别记录。玩法操作查[FEATURES](features.md)，验证数字查[BASELINE](baseline.md)，当前停点查[HANDOFF](handoff.md)。已确认规则是目标约束，不等于所有机制已实现。

## 当前主线与普通入口

| 名称 | 实际情况 |
|---|---|
| Git `main` / `origin/main` | 用户授权后已快进到`2e6b6a61caf11b5560c15a97f1a58cb156a7300b`，包含共同空间/最小行动及此前基础；该SHA CI已核success。新建筑包在独立分支，完整指针见Git与[分支页](branches.md) |
| 当前根目录检出 | `codex/general-buildings`；通用建筑与组合空间阶段，实际停点与待验项见HANDOFF |
| 普通 `Main` 游戏入口 | `scenes/main.tscn`及其运行接线；有限游戏能力和Git集成状态分别按功能及版本证据核验 |

通用参与索引、环境局部/到期执行与健康活跃集合已接普通Main并合入Git main。五个旧正式功能分支均已在main历史；`codex/field-contest`与命名stash保留为隔离旧实验，不是待发布功能或自动恢复任务。[集成记录](../qa/20261107_mainline_cleanup.md)保留来源和验证对应关系。

## 按顶层框架的实际接入

领域职责和交接以[顶层框架](../engineering/architecture/05-framework-domains.md)为准，框架出口以[基础建设计划](../plans/foundation-priorities.md)为准。下表包含main基础及当前建筑阶段分支的接入；版本与待验项见BASELINE，各顶层领域仍不能整体声明完成。

| 顶层框架 | 已有运行能力与主要入口 | 距框架出口的缺口 |
|---|---|---|
| **世界地块与空间框架** | [WorldMapData](../../scripts/sim/world_map_data.gd)、[ReolWorld](../../scripts/world/world.gd)；512²平面、64²显示区块、草/水/岩、稀疏地表改造；[SimWorldObjectQuery](../../scripts/sim/world_object_query.gd)与显式引用空间快照；`SimWorldSpace`组合身体/地面物/结构实时局部查询、冻结变更与恢复重建 | 普通地图规格固定，非任意规模生成；实时查询已覆盖现有身体/地面物/结构，未包含植物/衣物/全部容器；快照仍不枚举全世界；高差/多层后置 |
| **实体、物品与容器框架** | [SimEntityQuery](../../scripts/sim/entity_query.gd)、[SimEmbodiment](../../scripts/sim/embodiment.gd)、原身体；声明能力、连续位置与多格几何；[SimObjectLifecycle](../../scripts/sim/object_lifecycle.gd)、[SimInventory](../../scripts/sim/inventory_ledger.gd)、[SimGroundPlacements](../../scripts/sim/ground_placements.gd)支持受控实物生命周期、同账本转移、堆拆、预约和唯一原物 | 通用身体/植物/家具生命周期未覆盖；独特器物、衣物与数量保留不同原owner，跨账本搬运、负重/容量、箱中箱、自由背包及完整处分权限未完成；普通装配仍限两区 |
| **建筑与组合空间框架** | `SimConstruction`持原多格/朝向、材料施工、工地/用途与耐久；`SimConstructionGeometry`校验定义；`SimStructureQuery`/`SimEnclosedSpace`推导空间；`SimFacilityUse`接操作位、桌椅和真实储藏，`SimPersonalProduction`复用建成工作台；普通营造面板可使用 | 当前home账本/授权、有界工地和已实现能力；完整工艺、灯火/容纳环境、私人地产及跨区政策未接。房温归环境域，路径与主动攻击归行动域，最终证据见BASELINE |
| **植被与自然生命框架** | [SimLandResources](../../scripts/sim/land_resources.gd)有限自然资源和两处野药环境响应；[SimAvianLife](../../scripts/sim/avian_life.gd)雀生活/雀身；[SimLargeBodies](../../scripts/sim/large_bodies.gd)3×3山兽；残识/载体保持原状态 | 地表覆盖和资源记录尚非完整植物实例；通用植物生命周期、自然过程及普遍环境来源/受体未接；非人生命仍是有限类型，完整繁衍/成长/寿命与生态规则后续实现，巨兽不可选 |
| **环境框架** | [SimWorldEnvironmentFields](../../scripts/sim/world_environment_fields.gd)作为唯一室外冷热/五行实际响应；真实地面/固定来源、衰减/max、等级抵消、响应建立/消散和残留存读，人体/野药同温度；历法、地理新局编译、有限晴雨、自然日照、固定灯/随身固有微光与遮挡 | 随身物整体发源/尾迹/遮掩、容器透过及树兽墙材普遍发源未接；一房一温、隔热/开敞/拆合连续性未实现；完整雨雪/风/空气与五行后果后续实现，风水仅有规则；五行火不等于发热，光不等于冷热辐射 |
| **单位行动与交互框架** | [SimLocalMotion](../../scripts/sim/local_motion.gd)、[SimRouteTravel](../../scripts/sim/route_travel.gd)、多格扫掠及运行层寻路读原身体/空间；[SimInteractionRequests](../../scripts/sim/interaction_requests.gd)与原执行器区分表达/理解/意愿/耗时/中断/结果，耗时搬运已接普通面板；`SimActionContract`使取放/施工/家具使用共用条件、占用、复核、终态与释放 | 动作仍由各领域过程执行，门面列举20种事项；最小合同已接取放/施工/家具使用，全领域共同生命周期、接近/效果组合和策略入口未齐。动态路径失效/重规划属于本框架内部缺口；固定运粮仍保护原路，非全局动态绕路 |
| **认识与自主决策框架** | [SimSocialMemory](../../scripts/sim/social_memory.gd)私人认识/有向关系/来源、当面自述；[SimInstitutionBook](../../scripts/sim/institution_book.gd)任职公账和贡献；双聚落需求/职责/吃住/采集生产、预约、少量自主目的和互助；迷雾/探索提供有限观察接缝 | 新对象/属性未全面接共同观察与认识；通用目标/策略编排、工作依赖及授权依据仍有限；关系判断仍用有限因素加权/边界骰与逐人值。通用Claim为候选，现有贡献不等于Claim；制度与长程社会玩法后续实现 |

## 贯穿框架的运行与工具合同

| 公共能力 | 已有接入 | 未覆盖与验收边界 |
|---|---|---|
| 共同时间与远区 | autoload `GameClock`（`ReolGameClock`）、[RegionalSimulation](../../scripts/sim/regional_simulation.gd)；整数毫秒、固定阶段、预算欠算、双聚落离场接续、行旅/货运/消息 | 非所有领域事件化；大人口、多年与密集动态组合未验 |
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

集成代码有完整本机分片覆盖、各worker错误/退出门禁和一次既有代码包静态审查；前序版本另有普通Main完全停开、RTX3060稀疏负载/画面及两域存读/短测证据。既有CI42356120868的准确SHA已核success，main起点`b3ae3399`的CI42365643089已核success；本阶段建筑分支d00bac本机4片完整覆盖250组/126290检查通过，3份普通在途档完全停开后同未来，一次原生审查4项发现已修复；远端CI另按准确SHA待验，详情见BASELINE。

不能用前序截图/帧时替代当前版本的规模验收，也不能拿此前26万静态物品的旧版压力结果担保当前密集动态世界。当前没有证据要求换引擎，也没有证据宣称全游戏规模已达标。
