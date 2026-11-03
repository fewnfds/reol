# 当前代码架构

核对：2026-11-04，Godot4.7.2 / GDScript。本文描述**已有代码及其限制**，不是目标模块清单。可玩行为见[FEATURES](FEATURES.md)，格式与验证见[BASELINE](BASELINE.md)，文件职责见[PROJECT-STRUCTURE](PROJECT-STRUCTURE.md)。

完整游戏Goal保持active，按[超凡者主线](plans/transcendent_focus.md)优先能力、冒险、组织和事件化远区。U0的身体占用、固定域目录/有名结算阶段、公开候选绑定及纯JSON值规范继续支持后续领域。U1有限交锋/感知/借源/看护与U2-a本人本领来源/有限行气用法已验收；当前[U3-a野外连续性](plans/first_field_opportunity.md)已接入，**实施中、等待最终验收**，证据见[QA](qa/20261104_field_opportunity.md)与BASELINE。通用活动生命周期、完整事件队列、完整战争及引物环真实隔空用途仍待实施。

最新横向审查见[世界/人物/事件/地图](ARCHITECTURE-REVIEW-20261103.md)；E1历法、E2余热与E3药丛之后，[E4-a有限灵源](plans/finite_spirit_source.md)已接共同时间和原身体/器物。后续见[天地环境](plans/world_environment.md)、[真八方向外观](plans/eight_direction_appearance.md)。通用事件/实体注册、完整气候/室内热交换、五行场/风水不因目标架构图而算已实现；A1真八向技术样本已按[QA](qa/20261103_eight_direction_sample.md)接原body朝向与共用采样/分层。

本轮新增边界：`WorldMapData`借`NaturalEnvironment`确定地表/五行亲和与覆盖，缓存不是持久资源；活鸟仍由原`SimAvianLife`保存。`SimWorkplaces`只评估保存于地点的固定构件布局、原位置和原任职，公账仍归`SimInstitutionBook`，物资仍归原库存。屋面/阻挡接原施工查询以供身体、衣物和有限热场使用，不另造功能建筑钱包或第二份人物。细节与限制见[自然世界/场所](plans/natural_world_and_workplaces.md)。

长期房间/家具/容器设计见[建造与空间](../design/systems/construction_and_space.md)：空间/使用安排/操作能力/实物归处/人物权限/工作过程分别归属；围合与服务可用性派生，持久安排和进行中上下文保存。它是后续约束，当前未新增通用家具域或全量房间类型系统。

[U1-a](plans/transcendent_conflict.md)已接原器物能力类别、冲突域、挫伤来源与qi对账，实际验收见[QA](qa/20261103_transcendent_conflict.md)。过程目录和候选共用原身体：冲突在同一边界调度中处理精确发招、固定扫掠、同刻接触、退让和示范；`home(actor)`表示数据所有者，接触与学习范围由唯一全局位置判断。跨所有者见证复用已有共享个人记忆，原qi基准扩为首次引息/正qi施术检查点；不会造第二份身体、血量、蓝量或世界时钟。

[U1-b0有限感知](plans/conflict_perception.md)在原交锋域保存每人至多一条最后亲见；`conflict_perception.gd`按观察者自己的视距、同高度和实际遮挡生成当前线索。NPC移动只使用有效目击位置，攻击只用当前可见目标；护障判断另检查可见起势或真实来弹的方向与剩余射程，跨交锋归属仍按空间判断。它不读取玩家迷雾，也没有另设全局感知记录或NPC位置。

[U1-b1公源借用](plans/source_loan.md)新增`SimSiteAffairs`与严格候选：只保存显式地方安排、具名说明、一次借用note、原源尝试引用、申请者声明、核验者亲见与回桌登记。原`SettlementServices`执行`site_loan/service`和`site_return/inspect→register`；核验job的actor是管事，申请人在options.requester，原身体排他仍生效。回桌仅豁免该已验证job自身的服务占用，其余控制、伤势、劳动和场所检查保留。原贡献簿同一物理载体的附页限定`source_loan`用途，不把贡献余额或载体变成万能Claim。

原`SimSpiritSources.begin/_finish`同步绑定/释放/消费一次note；源量、qi、温石储量、保管与预约不复制。无许可仍可物理使用。查询不学习消息，申请人须当面再次请求才听到管事已登记的结果。旧根36/区域32显式升根37/区域33并仅补空事项；主局新建才显式装配case。事项先独立恢复形状，等原服务/源/器物/社会记忆全部恢复后交叉核验，最后原子替换。具体证据见[QA](qa/20261104_source_loan.md)，最终检查状态以BASELINE为准。

[U1-b2公源看护](plans/source_care.md)新增`SimSourceCare`：只保存有期限的具名安排、本人观察/通信依据、采信、警告和原交锋引用。主局新建显式给原石头两小时安排，原 profile、位置、需求、身体和个人生计继续有效；到场查看仍是原`check_kitchen`行动，不新增身体锁、移动器或巡逻实体。规则只覆盖原一源一石一人，不扩通用产权/执法。

看护只在本人实际在岗、可见并能当面通信时警告。`explain_source`转述本人已知签发记忆，沿原`social.learn`保存来源；公簿附页没有变成随身纸证，也不读取原note的隐藏使用史来替看护判案。初始宽限九十秒，期间原引息/预约继续；只到期重新核验后由`begin_source_care(warning_id)`开原驱离。同步的`conflict_starting→interrupt_occupation→conflict_started`保留原源取消凭据并双向绑定`encounter.cause`；不开第二套战斗。源恰好先完成、失视、需求/伤势/控制不允许或委托失效时不能强开冲突。

## 1. 已有依赖

```text
main.gd：场景与运行协作者装配
    UI/输入 → runtime命令适配 → sim规则、执行与持久状态
                  ↓                  ↓
           world空间/地形查询     data定义与开局装配
                  ↓                  ↓
         entities/ui可知呈现     persistence文件存读
```

`sim/`不依赖UI或节点路径；`runtime/`连接时钟、地形、玩家输入与可知投影，不拥有第二份社会余额。`WorldMapData`提供节点外的地形/高度/静态通行，`world/`负责区块呈现及动态障碍组合，`entities/`提供实体画面。内容定义不回写为运行状态。数据加载与运行装配仍有过渡边界，不是已完成全量通用实体架构。

当前业务autoload是 `GameClock`；另有第三方Godot AI的 `_mcp_game_helper`。AGENTS中的EventBus、EntityRegistry、SaveManager等是按需目标，**没有全部创建**。

## 2. 已实现的状态所有者

| 模块 | 当前权威数据/行为 | 不应由它另存的状态 |
|---|---|---|
| [GameClock](../scripts/autoload/game_clock.gd) | 共同整数毫秒、分钟通知、暂停/速度/等候、相位与帧欠算 | 各领域库存/动作结果 |
| [WorldMapData](../scripts/sim/world_map_data.gd) | 原固定生成器、地形/高度、静态通行；联合会话持有，视图借同一引用；独立候选从首次位置检查即使用另一实例 | 施工/兽身的动态占地、第二时钟、视图瓦片或尚未实现的可变地表delta |
| [SimWorldCalendar](../scripts/sim/world_calendar.gd) / [SimClimateRules](../scripts/sim/climate_rules.gd) / [SimEnvironment](../scripts/sim/environment.gd) | 无状态历法/地理室外温度、规则版本/启用边界、原人身最新未来负担采样；原精力回调只读缓存，变更前同步旧区间 | 不复制时钟、衣物/湿润、精力、空间余热、植物或灵源；不是完整室内空气/五行场 |
| [VillageSimulation](../scripts/sim/village_simulation.gd) | 人类actor身体、日常状态与装配；仍通过原actor保存一部分个人状态 | 鸟身或魂的伪人类副本 |
| [SimActionExecutor](../scripts/sim/action_executor.gd) | 原生日常/劳动阶段、预约、实际取用/携回、中断 | 独立背包或机构余额 |
| [SimRouteTravel](../scripts/sim/route_travel.gd) / [SimLocalMotion](../scripts/sim/local_motion.gd) | 路线段时序 / 手动速度、闪身阶段；位置/朝向都代理原身体 | 第二位置、体力池或独立世界时钟 |
| [SimInventory](../scripts/sim/inventory_ledger.gd) | 原容器数量、预约、受托处分限制/领用与结清、幂等转移/transform | 唯一器物的重复堆叠副本，不能把保管量当额外实物 |
| [SimEntrustedGoods](../scripts/sim/entrusted_goods.gd) | 原保管记录的用途/凭据/机构/归还地点校验、查询与旧明确在途迁移 | 不另存第二数量、背包/工作队列或全世界物权 |
| [SimLandResources](../scripts/sim/land_resources.gd) / [SimHerbEcologyRules](../scripts/sim/herb_ecology_rules.gd) | 原自然来源容量/相位、自然产生/雨水流入/采出；原药丛土水/温雨缓存与生长积分，成熟药仍留原库存源容器 | 直接生成到仓库的无劳动补给；不另造植物背包/人物或地形delta |
| [SimPersonalForaging](../scripts/sim/personal_foraging.gd) | 自留动作定义检查与显式迁移；实际预约/劳动/采出仍归原执行器和来源 | 不另存个人产物/劳动/贡献，不能把公差中途转换为自留 |
| [SimPersonalProduction](../scripts/sim/personal_production.gd) / [production_schema](../scripts/sim/production_schema.gd) | 本人批次/场所/在制工时与原身体任务；独立候选核对原库存投入/点火/完成/取回凭证，原需求查询外部劳动 | 不另存物料/背包/精力/贡献，不把原公差改为私人产物；未做工位/代工或自主商业规划 |
| [SimBudgetedLabor](../scripts/sim/budgeted_labor.gd) / [labor_schema](../scripts/sim/labor_schema.gd) | 机构现金条款、签约认识来源、原生劳动尝试/结算；原公库专款与验收服务联合校验 | 不另造身体、劳动计时/材料/钱包，不把同一劳动兼算贡献与工资 |
| [SimAutonomousLivelihood](../scripts/sim/autonomous_livelihood.gd) | 有限随身口粮意愿、公共寻找站序/重试与结果；区域共同决策边界调用原交谈/预算劳动/服务 | 不复制所知、职位、身体、劳动、钱包或库存，不查询远处掌权者坐标 |
| [SimSocialMemory](../scripts/sim/social_memory.gd) / [SimStockInformation](../scripts/sim/stock_information.gd) | 事件、个人所知/来源、有向关系与请求判断 / 从原记忆投影库存预期 | 第二仓库、“全世界都知道”的真相字段 |
| [SimInstitutionBook](../scripts/sim/institution_book.gd) | 任职与权限、正式记账、认可依据；固定值事房记录载体由原场所引用 | 私人关系、可携带/毁坏的通用账本实体 |
| [RegionalSimulation](../scripts/sim/regional_simulation.gd) | 区域调度/必要边界、在途货物、路线、运输与消息 | 另一套各地日常事实 |
| [SimEmbodiment](../scripts/sim/embodiment.gd) | 主体/载体引用、居留、移动/行动/通信控制通道 | 身体位置、库存、全部个人记忆 |
| [SimBodyGeometry](../scripts/sim/body_geometry.gd) / [SimLargeBodies](../scripts/sim/large_bodies.gd) | 无状态完整占地/净空/有界寻路；唯一兽身位置、地盘点、正在迈步/待行路径、重试与递食来源 | 不复制人类actor/背包/身体，不做全种族需求与超巨体跨区 |
| [SettlementServices及helpers](../scripts/sim/services/) | 访客服务、交付证据、机构办理、互助承诺/托管与实际完成支付 | 可绕过原资源/控制的即时奖励 |
| [SimHealth](../scripts/sim/health.gd) / [health_schema](../scripts/sim/health_schema.gd) | 原器物反噬与冲突真实命中来源的持续后果、双人诊治与未来分钟恢复；候选核对伤源/原材料/同意/身体 | 不重复精力/灵力；经脉与挫伤分别约束恢复/治疗，不是完整医疗/死亡 |
| [SimSparring](../scripts/sim/sparring.gd) | 有界自愿对练、短动作、接触去重和同刻结算 | 完整伤亡系统或第二份体力 |
| [SimConflicts](../scripts/sim/conflicts.gd) / [conflict_schema](../scripts/sim/conflict_schema.gd) | 有界多场驱离意图、当面示范、已付动作/阶段、投射/气障、命中凭据、有限最后目击与真实退开；空间和当前线索分别由[ConflictSpace](../scripts/sim/conflict_space.gd)、[ConflictPerception](../scripts/sim/conflict_perception.gd)查询 | 不持有身体/武器/伤势余额；不从旧线索读取隐藏新动作，尚无听声/神识/完整搜索、战争/致死/事件粗算 |
| [SimArtifacts](../scripts/sim/artifacts.gd) / [SimArtifactUnderstanding](../scripts/sim/artifact_understanding.gd) | 唯一器物保管、能力类别/动作；温石才有储能/裂损，真实木剑只携实物归处；进行中操作/个人认识 | 由查询自动学会的技能或全知属性；不要求所有物品都有热字段 |
| [SimCapabilityQueries](../scripts/sim/capability_queries.gd) / [SimCapabilityPractice](../scripts/sim/capability_practice.gd) | 本人原招式/器物/版本/木牍的只读来源投影；新增有限练习过程、原资源成本和完成证据 | 不建全局learned镜像、第二qi余额或第二移动身体；目录不直接授技 |
| [SimFieldOpportunities](../scripts/sim/field_opportunities.gd) / [field_opportunity_schema](../scripts/sim/field_opportunity_schema.gd) | 一处显式地点/固定槽、一个有限寻物目的、原身体行程与原取物引用；源线索/亲见仍存原个人社会记忆，联合候选核因果 | 不复制身体/器物/背包/时钟，不把POI变第三聚落，不授引物能力或提供通用任务/探索规划 |
| [SimSpiritSources](../scripts/sim/spirit_sources.gd) / [spirit_source_schema](../scripts/sim/spirit_source_schema.gd) | 固定源存量/有限深层释放/散失、源预约、原身体/温石的引息过程与输出凭据；原qi/charge基准用于跨域对账 | 不复制人物灵力、器物储热、身体/位置或时钟；不是全局五行余额/修炼等级 |
| [SimSiteAffairs](../scripts/sim/site_affairs.gd) / [site_affair_schema](../scripts/sim/site_affair_schema.gd) | 显式公源case、具名说明、一次note/原用源引用、归还声明/现场证据/登记；真实执行仍归原服务 | 不复制源量、器物、贡献、身体；签注不等于人物全知或便携文书 |
| [SimSourceCare](../scripts/sim/source_care.gd) / [source_care_schema](../scripts/sim/source_care_schema.gd) | 一处公源的有限看护安排、原查看action引用、本人说明/采信、警告/宽限与原交锋cause；独立候选核对原job/事件/身体 | 不保存第二身体/路径、源量、武器、伤势或许可余额，不提供通用巡逻/产权/执法 |
| [SimAvianLife](../scripts/sim/avian_life.gd) | 实际雀身、鸟嘴轻物、食源/栖地、本人所见与生活 | 套人类actor的双身体/双物资 |
| [SimSoulVessels](../scripts/sim/soul_vessels.gd) / [SimSoulAgency](../scripts/sim/soul_agency.gd) | 原戒与封纹、晏衡旧知/注意/约定/指导 / 玩家残识的有限接触、自报和携戒请求 | 持戒人的控制权、其全部关系/库存 |
| [SimSocialAdmission](../scripts/sim/social_admission.gd) | 声称/判断缓存、私人核验、一次临时放行及消费来源 | 正式贡献、永久通行或自主骗术计划 |
| [LocalTrade](../scripts/sim/services/local_trade.gd) | 原服务job的常备报价/签发、实际清点、双方完整预检/两笔交割与对应凭证校验 | 不另造订单/钱包/库存，不把公开政策当隐藏余量查询 |
| [SimInteractionRequests](../scripts/sim/interaction_requests.gd) | 无状态意图门面：结构、可见对象、通信/理解/身体边界与领域路由；按原记录查询后续 | 不另存同意、任务、知识、报酬或请求历史 |
| [SimHeatMethods](../scripts/sim/heat_methods.gd) | 不可变温养步骤/作者/版本目录；依据原器物事件判断个人试验/掌握，按原社会判断邀请学习 | 不另存学习余额、身体、储热或执行计时器 |
| [SimMethodRecords](../scripts/sim/method_records.gd) | 唯一木牍/版本引用、取放/自愿交接、写读过程和本人阅读来源；候选重演位置流转与核对原耗材/同意 | 不复制温养步骤、木料、身体或练成状态，不让目录变成全世界共享知识 |
| [SimConstruction](../scripts/sim/construction.gd) | 获准工地/地面与上层占地、工时、材料位置/携带者、搬运/施工/拆改/支撑塌回与职责 | 不另存木料数量、人物位置、全知NPC库存预期或第二世界时钟 |
| [SimEnclosedSpace](../scripts/sim/enclosed_space.gd) | 由工地实际墙/门洪泛得到的有限围合/面积/门口/平整缓存 | 不保存独立房间事实，不推导屋顶/温度 |
| [SimResting](../scripts/sim/resting.gd) | 公物床位分配、在途预约/实际休息/起身让位；恢复速率查询 | 不复制床、身体位置/精力或恢复余额；不是全面物权 |
| [SimWeather](../scripts/sim/weather.gd) | 气候起点/环境脉冲、两地晴雨只读查询、稀疏床湿润；受限雨水调用原来源 | 不另存泉源水量/床或身体恢复余额，不保存渲染粒子 |
| [SimStandingWork](../scripts/sim/standing_work.gd) | 原社会决定/见证支撑的有限劳动约定、期限与终止；查询本人临时劳动意图 | 不改原actor自主/职责，不另存工作/物资或保证结果，不向缺席者泄露进度 |

唯一器物的位置由其保管容器引用解算；主体/身体/操控者/物主分别表示。当前注册表跨域引用真实 `village_actor`、`avian_body`、`soul_vessel`、`large_body`，不据此声称任意换身、多身、植物或完整巨兽可玩都已接入。

## 3. 运行适配与玩家视角

| 协作者 | 职责 |
|---|---|
| VillageRuntime / WorldContinuityRuntime | 场景绑定、区域视图、行旅、公共命令/查询与恢复后的引用替换；按实际位置与FOW显示/点击原人物，数据owner不随行旅改变 |
| SettlementServicesRuntime / SettlementServicesPanel | 办事/采集/私人制作意图、阶段与本人批次/地点反馈；不是权限/库存判定所有者 |
| WorldObjectsRuntime / ObjectInspectionPanel | 可见器物、靠近/选择与获准理解；面板不读隐藏储能 |
| SpiritSourceRuntime / SpiritSourcePanel | 可见地火隙及本人位置记忆、原温石/本人或温石目标、同一引息按钮和本人倒计时；行路/停止走原运行入口，界面不拥有源存量或授予方法 |
| AvianLifeRuntime / PlayerAvatarRuntime | 可见雀妖、有限请求；会话一次性身份绑定、鸟身输入、视角/迷雾 |
| LargeBodiesRuntime | 地形中装配一次山兽、可见外形/当前动作绘制与点击指入原C请求；不保存另一份身体或远区实时认知 |
| SoulVesselRuntime / SoulVesselPanel | 人身向独立寄魂者提出意图与亲历对话 |
| SoulPlayerRuntime / SoulSenseView | 残识专用输入与有限匿名灵机；不暴露人类后台全图/身份 |
| SparringRuntime | K/J输入、获准阶段/扇区和收手；命中由sim决定 |
| ConflictRuntime | U本领/当面意图、Q/E/R暂停排队后真实提交、X停手、有限感知的前摇/气弹/气障；不在绘制帧推进规则 |
| [FieldOpportunityRuntime](../scripts/runtime/field_opportunity_runtime.gd) | L野外见闻、本人已知地点行旅/到场查看、当前可见物件跳转原I页和C问路；旧探索只画记忆，绘制/刷新不写知识或生物件 |
| InteractionRequestsRuntime | 人身C的眼前接收者/事项/对象/媒介、贸易份数与劳动分工/当面撤回、野外去处`field_clue`；借用依据说明、看护询问/参与者撤回；过程引用从原领域按个人可知重建，仅当前扮演主体实际收到的看护警告会停止等候、恢复一倍并暂停 |
| HeatMethodsRuntime | M手记的草案参数/本人版本、教学及实物记录页；刻牍/读牍仍由记录域执行，照步骤练习复用原charge任务 |
| ConstructionRuntime | N施工簿、工地/结构/木料/围合投影、床位安排与使用；调用原施工/休息规则 |
| WeatherRuntime | 所在地天气文字/有界雨线；只按共同时间重绘，跳过不可见/覆顶格，残识隐藏 |
| ReolUITheme / PawnVisuals / FacilityVisuals / PawnViewLayout | 样式、绘制、拥挤显示偏移；不写回真实路径或位置 |

会话保存所扮演的主体，不复制其身体。开局只选择一次，读档恢复原身份；鸟/魂模式下原人身自主。感知先按恢复身份建立，再恢复探索，避免旧人身资料泄漏。

野外人身仍归原home/river保存，查询状态先找真实owner，显示和相遇使用唯一全局位置；不同owner同格共用拥挤显示布局，选home人物会清旧river选择。FOW改变时也退掉不可见的远地视图，暂停不冻结可见性清理；隐藏/重建视图不移动身体。原寻物路线经[HumanoidPose](../scripts/runtime/humanoid_pose.gd)投影为八向步行，不增加动画位置。`centers`仍只有山门/河湾，野外`current_region`为空，不能据此称为通用多聚落运行层。

## 4. 共同时间与远近执行

`ReolGameClock.elapsed_ms`是共同整数毫秒；旧 `tick`保留为整分钟通知。默认现实一秒等于世界一秒，1/2/4倍共同缩放；这是可测试调整的默认，不是全游戏最终时间平衡。

原身体唯一保存连续位置，格子是其空间索引。`SimRouteTravel`沿几何段推进，NPC/自动路线按同一速度，到达后才计算完整劳动；`SimLocalMotion`处理玩家短动作。需求和体力用固定点余数避免粗细推进差异。视图/插值不能推进规则。

U2-a的`walking_projection`分开普通步行与原动作锁；Regional每个真实时间边界回调原手动身体积分，候选用同一投影核速度，命中边界立即收敛。原护障缓步须先完成付费练习，qi仍由原body唯一保存，源对账显式增加`practice_floor`，不由U页或动画帧改变。实际范围见[U2-a QA](qa/20261104_capability_network.md)。

近区细步，远区跳过稳定区间、处理最早必要变化；跨区写入先同步相关区域，改变条件后使预测失效。当前验证覆盖双聚落和已接领域，不能承诺任意物理轨迹逐位一致或大型世界帧率。路线仍基于格路，顺滑/避让属于后续实际测量事项。

自主生计只在村落先处理需求/凭据/已有照看约定后预留该次个人决策。区域推进到同一毫秒并结算原事务，再执行计划；失败回原日常。自主交谈/签约另核对当前决策戳、自主、原身体空闲与两级同刻，外部命令仍需消化完欠算；不临时改target_ms。实际寻人复用原生公共拜访，原工资/购买复用既有执行器。

U3-a寻物同样经原initiative交接，只在本人有来源线索、原生活/备粮/职责/需求/伤势允许时用原身体开始`SimRouteTravel`行程，到场经原器物`take`取得同一环后返回。阻路、失控、冲突或身体需要可中断，保留结果回原日常；地点观察时点可唤醒已到期且空闲的意愿，实际优先级仍由原决策器决定。存在地点时当前每两秒采样有限人物的亲见，显式到场也可观察，UI帧不决定结果；历史最多64段行程，满后停止新增。这个永久采样成本与有界历史仍只适合当前样本，尚未验多年/海量世界或完整事件化远区。

有限灵源使用同一`elapsed_ms`，以原启用时刻保留十分钟释放相位，有限补给可按区间整数结算，满后记散失、深层耗尽后停止。引息完成与源释放参与原区域必要边界，欠算仍留原target；卸载视图不取消源或过程。NPC只在原需求/健康/衣着/职责/承诺后的本人决策时刻，已懂方法、实际近源且原灵气不足一次温养成本时考虑归身；不查询远方余量或另起寻源规划，提交失败回原日常。

交锋按原必要边界先同步参与者并采样目击，再移动和处理实际接触；同刻命中收集后统一提交。随后先形成所有活跃场次的当前决策线索，再提交各NPC起势，后场不能读到前场本边界刚作出的决定。失去视线后只趋近未过期的最后所见处，不继续跟随隐藏坐标；退让也只采用有效目击或自身朝向。感知目前仍按原细步推进，不是已完成的大规模远区战斗粗算。

交锋自动方不再固定为defender：每位参与者按原自主前态及真实`embodiment`控制通道决定是否自行行动，手动玩家被驱离仍不自动施法。看护的个人决策先在原村落initiative中预留，再到共同毫秒的未来决策阶段提交；原需求、凭据、承诺和个人生计先行，不在村落提前推进时读未来世界。只在相关活源且本人可查看或已有警告时启用有限观察边界；没有事件时停轮询。原源完成、既有交锋、需求等先结算，再处理看护升级，粗细推进共用这些有名边界。玩家离场不重建人物或复原源。

尺度样本在每步开始前同步原人物，再检查完整占地及其在途格；一步期间占用起止覆盖并集。ReolWorld的动态阻挡组合原施工与兽身，施工/落鸟也读取同一占地。玩家自动行旅先在兽身边界分段投影，避免粗推进把玩家未来位置提前拿来结算山兽。3×3方形四向转身不改覆盖；尚无长条体转向扫掠/任意角旋转。候选静态净空只读自己的墙与原地形，不能读活世界的兽身。

## 5. 提交、存档与引用

U0使候选边界经`home_runtime()`与`VillageRuntime.snapshot_context/valid_snapshot/matches_snapshot_world`取得必要引用；[SnapshotValues](../scripts/persistence/snapshot_values.gd)只处理JSON值规范/形状，保留旧static包装供历史调用使用。Regional使用固定域目录进行保存/形状检查和边界查询，领域内容与跨域验证仍专用实现，根/区域格式不变。候选提交用领域公开`bind_world`，不初始化/重置已恢复过程。当前兼容home副本仍须严格相等，没有借重构静默覆盖一侧。

[WorldSessionSnapshot](../scripts/runtime/world_session_snapshot.gd)在一致时刻组装联合快照，构造独立候选并交叉检查；成功后WorldContinuityRuntime才替换场景引用与时钟。[SessionSaveSchema](../scripts/persistence/session_save_schema.gd)显式迁移历史格式；[SimSaveStore](../scripts/persistence/save_store.gd)负责JSON文件、备份与原子替换，不决定业务成败。

领域各存自己的状态与进行中事务，来源/控制/时间/引用共同校验。固定生成器描述与探索进入会话；可见范围从恢复位置重算。当前格式及不可改写的真实旧档目录统一见[BASELINE](BASELINE.md)。

U3-a先恢复地点形状与固定槽，再恢复原器物候选，等身体/社会记忆/路线/器物等原所有者齐备后核线索来源、亲见、行程和唯一器物保管因果。根候选的`site:<id>`目的地按该候选本人的知识核对，不借活会话后来所知，不允许额外目标坐标覆写。旧档显式迁空新域，不补遗迹、环、线索或旅行；普通主局新建通过`WorldContinuityRuntime.setup`的`opening_field`显式启用，读档整域替换而不根据开局flag补物。真实进行中与坏候选证据见[本包QA](qa/20261104_field_opportunity.md)，当前格式/最终回归只看BASELINE。

感知包当时形状为根36/区域32/交锋2；当前格式以BASELINE为准。`perception_since_ms`明确启用边界，`people[actor].sight`为空或保存目击时刻、观察者当时位置、对手当时位置及高度。旧v35在保存现在启用且线索为空，原动作、费用、弹、障、伤势及已经决定的退让方向保留；更早迁移固定产生当时交锋1形状，再显式升版。候选检查记录字段、时间、有限距离和记录点的静态高度，但不拿此刻人物位置或门墙证明过去可见；同毫秒后续移动也不改写旧观察。这是有界历史记录的一致性校验，不是完整感知事件重演；本包最终验证状态仍以BASELINE为准。

看护域先独立恢复严格形状，等原case、源、社会记忆和交锋全部恢复后再核原job、个人说明/决定、观察几何、取消凭据及warning/cause双向引用。历史观察不拿今日墙门或人物位置补证；引息的历史固定位置与源地点可核，不冒充完整历史重演。旧局显式迁入空看护，原交锋cause为空；不因已有地火隙、公簿或人物就追补值守/警告。运行适配恢复后先核当前玩家主体已收到的活警告，再允许钟继续，避免临近截止的真实警告被第一步跳过；鸟/魂开局的原人身事件不泄漏给玩家。当前格式与最终证据仍只在BASELINE维护。

[地图数据拆分](plans/world_map_foundation.md)不增加空delta或迁档。`RegionalSimulation.map_data`持有联合会话地图，`ReolWorld`代理原查询并混合原动态门墙/兽身；施工和多格身体的静态回调直接指向数据。根stage先建独立候选地图再查玩家位置/路线，区域内部临时世界借同一候选数据，施工重索引在床铺/天气/热场恢复前完成。全部通过才替换会话与视图引用，清除原所有高度层/悬崖/区块队列后重绘。合法路线的未来动态受阻仍由原执行机制处理，不能按活墙拒绝旧候选。独立村落加载同样使用候选地图；测试平地通过显式数据替身注入。

稳定引用须带作用域：人物、领域对象、事务与本地事件ID不能因字面相同便当成同一对象，跨域引用需声明来源；NodePath和数组位置不能充当存档身份。实际取得与正式认可分别提交；同一事务不重复产生物品、学习、命中或记功。

行动占用通过`owns_for_scope`只读原领域状态，固定八种用途保留对练阶段和callback边界；`body_action_owns`可排除自身。它不是新锁表，主体控制通道、原生日常`active`、施工/休息职责意图仍分开。结算阶段明确先结旧区间→原到达→原当前过程→环境采样→未来决策/消息与派送，阶段内部保旧顺序；这只是现有调度整理，完整远区事件队列仍待U主线。

温养目录在候选器物动作前恢复，以校验不可变版本/实际时长/投入；教学还校验教师先前练过、原社会同意、师生互斥与指导成本。老师是原动作的协作者，取消/控制丢失同步释放双方并保留既付成本。人物原自主来源含操作/指导前值，鸟/魂玩家不会因别人的暂时学习而被误判换回人身。

实物记录在目录后、器物候选前恢复，引用原版本而不复制步骤；原库存consume凭证支撑刻写，起止标记核对身体/木牍占用与唯一位置流转，完成的本人阅读才授权照文尝试。全部领域恢复后再核对读者当时的原基础与当前身体互斥。木牍随原持有人/设施引用解算位置，跨区同意用原服务社会记忆，人物和包不迁复制。旧v22显式迁空；没有物理记录的历史不补造。

施工项目的材料数量仍在原村落库存；项目容器的carrier/material_cell只说明那批料在谁手中或何处，不复制背包。村落校验仅接收父施工域明确列出的额外容器/预约/操作，之后施工域再核验完整凭证、工时、占地和身体互斥。候选空间以静态地形加自己的结构检查，不读取活世界的墙；ReolWorld分别提供静态地形与动态通行入口。未来路线被堵是合法待处理状态，不为读档强行穿墙。

围合缓存随结构变化重算，门口的拓扑分界与物理开关分开；覆盖另查该格真实完工屋面与同高支撑，不从围合推导。床沿用施工项目，床位/休息单独在SimResting；travel→sleep→leave仍读写原身体。VillageSimulation的非持久恢复回调把床上精力恢复与原消耗合并为固定点净速率，沿用need_carry；途中/起身不额外恢复。远区选床检查前同步原身体，醒后走离床格再释放。候选在施工恢复后交叉校验床引用、分配、排他、路段、时刻和身体互斥，再绑定回调；不把活世界的缓存/闭包当存档。

环境整分钟脉冲在同刻施工前结算上一区间，改湿润/接雨前先同步受影响区域，实际发生变化才失效其预测；满泉/无床的安静地区继续懒推进。SimResting按湿床条件查询恢复速率，不复制原energy。来源候选先按天气起点的实际降雨脉冲上界核验rainfall，天气恢复再交叉检查床完成时间/湿润上界/相位；非法雨水不能授权任意资源流入。v17以旧保存时刻迁入新气候，不倒造过去。

交易原job保存当面签发者/办公室/份数及固定条款，沿原service路线与耗时执行；清点前不交割。成功前对钱货两条不重名资源腿、容量、可用预约/库存与对应操作ID全部预检，无await的同一提交内调用原转移；成功必须有两笔配对凭证，未成功不得有半笔。机构现金沿原records容器，无新增启动金；当下任职决定未履约意向能否兑现，既成买卖保留其签发记录。政策不透露当前库存/预算，个人产权与批次来源仍未全面建模。

自留forage与公差gather是不同意图，共用原自然来源、库存预约、actor.active和完整劳动。forage必须从源实际采出才结束，即使行囊已有同物也不跳劳动；产物留包且不发公共交付凭据。UI模式仅映射下一动作。旧v19只给已有来源配置加入未来个人动作，不补资源/经历、不改原公共工作用途；更旧无来源仍无来源。

本地haul/gather/recipe与跨区运粮领用后，原inventory.custody保存整批用途/机构、原操作、归还与交付处；原数量仍只在原容器。available扣除未结受托量与普通预约，保护量合计不能超过实物。指定公差用对应记录交付/消耗并原子结清，重做认原批次；私物不被公差自动取代。原service的return_goods实际走回供给点清点后转回一批，不发功，失败/取消不解除责任。

村落候选验证本地领用/结清和进行中用途，父服务域再核对跨区领用/实际归还；现代缺记录或坏引用拒绝。旧v20只给明确尚在进行的公差建立现有责任，不追认旧已取消的混合物。根与区域原村落先保持一致，再显式迁移，不用重写根库存掩盖差异。完整产权、故意侵占/追偿/执法与通用组织仍未实现。

常备劳动约定保存原社会决定/见证、双方/计划/固定时段与终止；原村落在需求/报工之后经非持久duty_provider读取临时意图，不回写config职责或actor.autonomous。本人所见/听说决定检查/干活，原执行器/保管链负责实际公差。区域在共同期限边界结算，不取消已经进行的原工作；旧v21迁空约定。独立候选核验同意、条款/相位/互斥、原事件和反向决定引用，不能仅删约定来消除承诺。重建UI按本人原约定保留过程引用，远处私下撤回不瞬传，近处只查公开动作而不读取私有goal。

预算劳动签约先复核现任付款权、本人认识和同消息后承诺量，原库存实款转入labor:N专款容器；原生action开始/结束回调只给合同添加原action引用。同次原社会完成事件的work_credit为0，不生成贡献凭据。原服务claim_wage仍走路/耗时，完成时重验现任、原交付与专款后实际支付。中断/期限不复制受托物；已交付的未验工资跨期限保留，未挣专款按原transfer退回，满库留存待退。恢复先声明额外库存引用，再对原社会事件、资金/交付/零贡献、服务和期限做联合候选校验；v25显式迁空，无新增现金。

SimCapabilityConversation为无状态投影/通信协作者：自述来自本人日常实践、辨材背景、实际温石学习与现任职，社会意愿/同条件缓存沿原evaluate_request。答复只存原村落社会事件，跨聚落双方改用已有服务社会记忆；文本/声明白名单、私下决定和事件双向引用在原候选验证。不另存能力/知识库或授予听者技能。C重开只读本人收到的旧话，不远程读取当前能力；格式保持原26/23/5、旧档不补造交谈。

SimLocalHeat拥有固定空间键的正余热，既不归房间编号也不归人物；原器物完成warm扣原charge，再留下唯一来源回执。区域共同时间先结热旧段，真实结构改变前结旧布局、后重采新通量；拆墙/塌顶不删除或复制存量。整数冻结通量保证额外时间切分不多舍入；显式室外浴记录散失，内部成对转账。无通量微量残余不持续唤醒。原环境每分钟先结人物旧负担，再固定热历史样本，新增热分量只影响未来；NPC未来预览仅只读投影当前冻结段，超段明确未知，真实initiative交接后才在提交时刻复核执行。候选恢复原器物/施工/健康、热源/通量/几何和环境历史，全部通过才提交。首包最多512个永久激活格、满后拒源，仅有限正余热近场，不是完整绝对热力学或连续移动源。规则及产权/载体/空间的后续边界见[供暖规格](plans/local_heat.md)、[参考研究](../design/research/environment_sources.md)。

SimSpiritSources独占源账，不持有人物灵力或温石储热。开始仅预约同一源、原身体和原石，保存精确连续位置；完成前重核手法、控制、伤势、位置、保管与容量，成功同刻扣源并写原qi或charge。目标缺额之外的转化明确损失，不返还源成本，取消无产出。原器物/寄魂指导与源过程双向排他；运行适配用`hold_player_motion(true)`保留非格心位置，行旅须先停引息，过时的源停止按钮不取消别域工作。

源候选在原身体/器物/指导等领域恢复后联合核验：开局与释放之和等于当前、实际成功支出与散失，过程ID连续且活预约不能超订；逐时源账不能通过同刻借未来供给。首次使用建立原qi及器物/寄魂已分配ID下界，之后按原真实成本和新引息输出核对；存石另建原charge/损坏基准，核原温养、释热、裂损等历史，不只检查上下限。原在途成本已含基准，不重复扣。已完成历史和活过程也核身体/温石跨域排他，伪造产出、免费改qi/charge或缺失来源原子拒绝。真实旧档只从保存现在启用未来源供给，不补恢复或旧引息；格式与最新验证只看BASELINE，范围见[E4规格](plans/finite_spirit_source.md)和[QA](qa/20261103_finite_spirit_source.md)。

## 6. 共同不变量与未完成的接缝

- 输入只是意图；实际提交复核权限、控制、工具/资源、位置与地形。业务失败返回结果，不用assert代替正常失败。
- 同一控制通道有明确所有者；原生工作、服务、器物、对练等不能争用同一执行权。过程可中断，实物保留，未完成不发结果。
- 个人知道、相信、愿意与机构承认分别表达；面板、公开活动和诊断不能自动教会所有NPC。
- 当前动作体系仍有多个专用入口。辨物/衔药/常备买卖与照看分工/当面撤回通过无状态协议门面路由，NPC人类也可提交相同意图。过程引用带domain/id/performer；查询不得泄露第三人私结论或远处交付事实。有限能力自述已接本人私下记忆，通用能力推理/协商、任意动作/条件、玩家脚本与AI接入仍待实现；[最新交互原则](../design/systems/world_interaction_principles.md)是目标。
- 共同多人过程、通用持续作用/热力学、全面物权、完整有限规划、动态世界装配、完整气候/温度/室内/伤亡/出生等需随真实场景接入；已有施工/围合/床铺/屋面和雨水仍是有限样本，不能把架构表当完整领域能力。
- `scripts/social/succession_resolver.gd`仍是独立提案，未接游戏继任；没有全局万能声望或顶层发展度来替代真实过程。

原接缝调查留在[W0-a状态目录](plans/world_state_contracts.md)，它记录调查当时发现，已解决项以本页和QA为准，不把旧“时间仍分钟/玩家写回位置”等当当前事实。旧技术草图和本次整理前全文见[archive](archive/documentation_before_consolidation_20261103/INDEX.md)。

## 实物衣着接缝

SimClothing只持有唯一衣物/owner与保管引用/worn、湿润和原身体的取放穿脱事务；衣物不同时记成SimInventory数量。原人物位置、能量固定点余数、任职与知识保持原所有者。天气脉冲先按旧速率同步受影响人物再改湿润，村落只读exposure_rate加入原消耗；全域晴朗/干衣不唤醒远区。两地气候采用最近住处和分钟末位置/屋面采样，不精确回放每段移动暴露。

衣着个人决策沿需求/凭据/原承诺后的initiative预留，区域同刻执行；原身体与全部领域互斥。候选在原领域恢复后，从有限开局物件与完成事件重演唯一位置/穿法，核对时间/原身体/连续位置、同位排斥与过去降雨上界，成功才提交。旧档显式迁空；非零时刻为读档实例化的临时场景不发新衣。ClothingRuntime只提交意图与本人/眼前可见投影，PawnVisuals绘制独立层，父Node2D承载纸娃娃缩放。

A1呈现接缝：`HumanoidPose`只读原身体/过程，`HumanoidAppearance`共享纹理/manifest与共同相位，`PawnVisuals`为玩家/NPC/V预览绘制；解剖锚点与前后片不创建物件或业务。原body只新增最后面对方向，动画缓存和预览不保存为世界状态；详细边界见[A1规格](plans/eight_direction_sample.md)。
