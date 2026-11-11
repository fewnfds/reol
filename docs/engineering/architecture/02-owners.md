# 当前代码架构与边界：状态所有权

本页为现存Demo的实现参考；重构目标由[执行规格](../../specs/world-engine/execution.md)定义。逻辑职责/有效规则不绑定下列class、数据结构或调用链。

## 状态所有权

本表定位现有原owner；[顶层框架](05-framework-domains.md)说明其领域职责与共同接口。一个class提供跨域适配不代表多个框架可以各持一份状态；职责划分也不表示相关目标已经完成。实际接入与缺口按同一框架在[功能范围](../../status/features.md)登记。

| 领域/代码入口 | 权威状态或行为 | 边界 |
|---|---|---|
| [GameClock](../../../scripts/autoload/game_clock.gd) autoload（`ReolGameClock` 类型） | 共同整数毫秒、暂停/倍速/等待、相位与帧欠算；唯一executor先完成原世界才发布 | Village绑定真实推进；部分/零提交留原请求，通知不二次推进；pending存档拒绝，分钟是投影 |
| [WorldMapData](../../../scripts/sim/world_map_data.gd)、[NaturalEnvironment](../../../scripts/sim/natural_environment.gd) | 版本化底图加稀疏地表覆盖，通行读同一真值；派生地表/植被覆盖/五行亲和和缓存 | 当前512²格；草稿/存读及暂停开发画笔已接，玩家合法改造待接；亲和不是能量库存，覆盖不是独立植物 |
| [SimTerrainEdits](../../../scripts/sim/terrain_edits.gd)、[TerrainEditorRuntime](../../../scripts/runtime/terrain_editor_runtime.gd) | 原地图上的小批量事务、空间预检；开发工具负责暂停准备和输入投影 | 显式启动才开放；沿原active/位置/施工材料引用，单笔最多256格，不发放玩家权限或平行状态 |
| [VillageSimulation](../../../scripts/sim/village_simulation.gd) | 人类原身体、唯一位置/朝向、原生活状态和村落配置 | 所属区是保存所有者，不是人物当前所在空间 |
| [SimBatchExecution](../../../scripts/sim/execution/batch_execution.gd)、[SimActorAdvance](../../../scripts/sim/actor_advance.gd) | 前者持有可回收的CPU批任务；后者持有原人物连续推进的紧凑输入/候选结果 | 不持第二份身体/时钟/库存；由VillageSimulation验证后采用，见[批执行](../execution-batches.md) |
| [WorldOpening](../../../scripts/runtime/world_opening.gd)、[RegionalSnapshot](../../../scripts/persistence/regional_snapshot.gd) | 新局发行与存档候选构造分别归属；前者装配，后者捕获/校验/恢复 | 不持久保存第二个世界；读档不重跑新局，领域存读登记在`persistence/world_save_domains.gd` |
| [RegionalSimulation](../../../scripts/sim/regional_simulation.gd) | 区域同步、域装配、共同边界/积压和跨域校验；`schedule_contract()`返回有序目录及阶段副本 | 领域状态仍归原owner；阶段目录描述既有调用顺序，不是自动事件总线或任意世界工厂 |
| [SimEventQueue](../../../scripts/sim/execution/event_queue.gd)、[SimWorldEvents](../../../scripts/sim/world_events.gd) | 离散请求、到期/等待、重复/取消/期限与回执；可信规则接原域效果 | 不是第二个时钟或世界事实仓库；[事件合同](../event-contract.md) |
| [SimPlants](../../../scripts/sim/plants.gd) | 原植物身体、年龄/生长/残根、环境条件、行动与觉醒后关系 | 产物归原库存，花盆水/支撑归建筑，主体归Embodiment；[植物合同](../plants-contract.md) |
| [SimLocalMotion](../../../scripts/sim/local_motion.gd)、[SimRouteTravel](../../../scripts/sim/route_travel.gd) | 手动/闪身及自动路段推进，读写同一身体 | 不复制位置、体力或时钟；显示插值不推进规则 |
| [SimMotionClearance](../../../scripts/sim/motion_clearance.gd) | 只读解析原过程当前首段及对角扫掠；固定运粮道路保守清场 | 不保存第二套位置/路线；施工新增阻挡和兽身清场复用，动态路线细节见结算合同 |
| [SimEmbodiment](../../../scripts/sim/embodiment.gd) | 主体、载体居留、移动/行动/通信控制 | 居留不等于控制，控制通道不等于行动占用 |
| [SimEntityQuery](../../../scripts/sim/entity_query.gd) | 无状态、只读地解析人物/雀身/独特器物/大型身体/植物的原位置与记录所有者 | 不登记第二实体表、不推进时间；区域滞后和世界积压分别标明，不能直接作玩家所知 |
| [SimStorageQuery](../../../scripts/sim/storage_query.gd) | 无状态解析原区域/鸟域容器与数量条目；身体/地点/工程/鸟身提供原锚点 | 引用限定domain/region/container，数量多item；不生成实物、同步或赋予搬运权限 |
| [SimArtifactTransfers](../../../scripts/sim/artifact_transfers.gd) | 原独特器物归处的同步可拒绝预检与完整事务后通知 | world持有会话钩子、器物域公开；无库存/位置副本或持久事件，不是通用搬运或玩家知识 |
| [SimObjectLifecycle](../../../scripts/sim/object_lifecycle.gd)、[SimGroundPlacements](../../../scripts/sim/ground_placements.gd) | 原器物/数量账本的命令事务、共同耗时动作；地面仅持有引用和多格位置；派生桶/容器索引 | 权威接口不授玩家距离/社交权限；只接显式physical定义及同账本材料；旧实物/数量不复制；[合同](../object-lifecycle-contract.md) |
| [SimInventory](../../../scripts/sim/inventory_ledger.gd) | 容器内堆叠数量、预约、操作与受托责任 | 责任引用实物，不再存一份数量；不等于完整产权 |
| [SimArtifacts](../../../scripts/sim/artifacts.gd)、[SimClothing](../../../scripts/sim/clothing.gd)、实物方法记录 | 独特物件位置/来源、穿法/湿润、有限器物过程与阅读记录 | 不同时复制成普通数量库存，持有/看见/读过不等于学会 |
| [SimSocialMemory](../../../scripts/sim/social_memory.gd)、[SimInstitutionBook](../../../scripts/sim/institution_book.gd) | 本人有来源的认识/决定；机构任职和贡献记录 | 关系/礼遇/权限/实际履约分开；未实现通用ClaimBook/司法/继任 |
| 原action executor、服务、劳动/生产、交换等域 | 各自过程、阶段/成本/证据与原资源引用 | 统一请求、共同动作投影/终态与集中中断均为薄接缝；原services持数量搬运jobs/回执，原库存持数量/保管，不新增任务库；任意条件协商仍未实现 |
| [SimConflicts](../../../scripts/sim/conflicts.gd)、[SimSparring](../../../scripts/sim/sparring.gd)、[SimHealth](../../../scripts/sim/health.gd) | 招式/弹障/成本、有限对练、真实伤源与恢复 | 使用原身体、灵气（`qi`）与体力，不另造战斗人物；非完整致死/医疗/战争 |
| 日历/气候、weather、environment、spirit_sources | 历法与天气、人体采样及有限灵源/转换，各自持有相应状态 | 热、五行亲和、物品可用灵气及有限灵源不合成万能数值；人体与植物采样读取同一普通环境域 |
| [SimWorldEnvironmentFields](../../../scripts/sim/world_environment_fields.gd) | 普通世界室内外实际温度、五行响应与相关来源/样本的唯一环境域；运行字段为`environment_fields` | 缓存与来源索引可重建，不另持实物；房温、墙门/屋面与材质传播见环境合同；详见[合同](../world-environment-contract.md) |
| [SimWorldEnvironmentSourceParticipant](../../../scripts/sim/world_environment_source_participant.gd)、[SimWorldEnvironmentBackground](../../../scripts/sim/world_environment_background.gd) | 前者预检并发布原物来源变更；后者为未受源影响格提供气候区共享背景响应 | 不拥有原物或独立世界时钟；内部来源可续算并采用GPU候选，外部命令仍有同步准备成本；详见[合同](../world-environment-contract.md) |
| [SimGeographicClimate](../../../scripts/sim/geographic_climate.gd)、[ReolGeographicContent](../../../scripts/data/geographic_content.gd)、Main开局配置 | 新局地理草稿编译成原climate2曲线，隔离重建完整内容包/digest并校验后装配；默认草稿为world_geography.json | 只在创建时执行，无运行温度附加项或第二状态；普通Main只支持原时钟起点，恢复仅取档内曲线，不重编 |
| [SimLocalLight](../../../scripts/sim/local_light.gd)、[LocalLightRuntime](../../../scripts/runtime/local_light_runtime.gd) | 即时相对光读原热出流或固有发光器物ID索引，位置沿原承载者/地点查询；共用遮挡、叠加、当前视野纹理 | 索引派生只读不落档，无第二物品/光量/位置；动锚点旧时刻或欠算返回unknown；当前128源/441格，照明不持有热量或燃料账 |
| [SimSolarRules](../../../scripts/sim/solar_rules.gd)、[SimNaturalLight](../../../scripts/sim/natural_light.gd)、DayNight | 从已接受世界的climate2、原物理时刻/天气、屋顶事实派生太阳高度/昼长/自然光，普通界面与天色读取同源 | 无第二时钟/光量账/持久缓存；单地图宏观纬度；不是局部灯、完整感知或植物受光模型 |
| construction / facility_use / workplaces / resting | 多格结构/家具身份、耐久与施工，操作位/储藏过程、固定办事布局和床位；库存/生产仍归原owner，详见[建筑合同](../construction-contract.md) | 围合、覆盖与功能分开；传播和房温读取实际墙门/屋面及材质，房间也不自行发行贡献或资源 |
| [SimStructureQuery](../../../scripts/sim/structure_query.gd)、[ReolWallVisuals](../../../scripts/world/wall_visuals.gd) | 无状态投影原结构引用/覆盖格/层与独立物理事实，按四邻绘墙 | 不复制实体或写档；真实木墙门的视线不等于桌柜碰撞，成功施工通知经runtime使本地视野失效 |
| avian_life / soul_vessels / large_bodies | 雀身、残识与载体、3×3兽身的原持久状态 | 不是人类伪装副本；兽身不可选、无完整物种生成/繁衍 |
| field_opportunities / site_affairs / source_care | 地点、许可/核验、具名职责/个人线索与原过程引用 | 有限样本，不能当成通用任务/产权/组织平台 |

具体域的文件、过程及验证入口按[计划索引](../../plans/README.md)和[FEATURES](../../status/features.md)查；旧逐域实现细节见[整理前架构](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/archive/documentation_consolidation_20261104/docs/ARCHITECTURE.md)，其中当时的版本和待办只作历史。
