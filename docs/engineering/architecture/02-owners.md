# 当前代码架构与边界：状态所有权

## 状态所有权

| 领域/代码入口 | 权威状态或行为 | 边界 |
|---|---|---|
| [GameClock](../../../scripts/autoload/game_clock.gd) | 共同整数毫秒、暂停/倍速/等待、相位与帧欠算；唯一executor先完成原世界才发布 | Village绑定真实推进；部分/零提交留原请求，通知不二次推进；pending存档拒绝，分钟是投影 |
| [WorldMapData](../../../scripts/sim/world_map_data.gd)、[NaturalEnvironment](../../../scripts/sim/natural_environment.gd) | 版本化底图加稀疏地表覆盖，通行读同一真值；派生地表/植被覆盖/五行亲和和缓存 | 均仍512；草稿/存读及暂停开发画笔已接，玩家合法改造待接；亲和不是能量库存，覆盖不是独立植物 |
| [SimTerrainEdits](../../../scripts/sim/terrain_edits.gd)、[TerrainEditorRuntime](../../../scripts/runtime/terrain_editor_runtime.gd) | 原地图上的小批量事务、空间预检；开发工具负责暂停准备和输入投影 | 显式启动才开放；沿原active/位置/施工材料引用，单笔最多256格，不发放玩家权限或平行状态 |
| [VillageSimulation](../../../scripts/sim/village_simulation.gd) | 人类原身体、唯一位置/朝向、原生活状态和村落配置 | 所属区是保存所有者，不是人物当前所在空间 |
| [RegionalSimulation](../../../scripts/sim/regional_simulation.gd) | 区域同步、域装配、共同边界/积压和跨域校验 | 现有固定域目录，非任意世界工厂/完整事件平台 |
| [SimLocalMotion](../../../scripts/sim/local_motion.gd)、[SimRouteTravel](../../../scripts/sim/route_travel.gd) | 手动/闪身及自动路段推进，读写同一身体 | 不复制位置、体力或时钟；显示插值不推进规则 |
| [SimMotionClearance](../../../scripts/sim/motion_clearance.gd) | 只读解析原过程当前首段及对角扫掠；固定运粮道路保守清场 | 不保存第二套位置/路线；施工新增阻挡和兽身清场复用，后续路线重规划仍待接 |
| [SimEmbodiment](../../../scripts/sim/embodiment.gd) | 主体、载体居留、移动/行动/通信控制 | 居留不等于控制，控制通道不等于行动占用 |
| [SimEntityQuery](../../../scripts/sim/entity_query.gd) | 无状态、只读地解析人物/雀身/独特器物/大型身体的原位置与记录所有者 | 不登记第二实体表、不推进时间；区域滞后和世界积压分别标明，不能直接作玩家所知 |
| [SimStorageQuery](../../../scripts/sim/storage_query.gd) | 无状态解析原区域/鸟域容器与数量条目；身体/地点/工程/鸟身提供原锚点 | 引用限定domain/region/container，数量多item；不生成实物、同步或赋予搬运权限 |
| [SimArtifactTransfers](../../../scripts/sim/artifact_transfers.gd) | 原独特器物归处的同步可拒绝预检与完整事务后通知 | world持有会话钩子、器物域公开；无库存/位置副本或持久事件，不是通用搬运或玩家知识 |
| [SimObjectLifecycle](../../../scripts/sim/object_lifecycle.gd)、[SimGroundPlacements](../../../scripts/sim/ground_placements.gd) | 原器物/数量账本的命令事务、共同耗时动作；地面仅持有引用和多格位置；派生桶/容器索引 | 权威接口不授玩家距离/社交权限；只接显式physical定义及同账本材料；旧实物/数量不复制；[合同](../object-lifecycle-contract.md) |
| [SimEnvironmentGroundCache](../../../scripts/sim/environment_ground_cache.gd) | 原地面物投影的派生来源槽及16×16基础目标缓存；有界计算、局部失效、epoch校验 | 生命周期通知前失效；查询不推进时钟，不拥有实际温度/五行残留或普通存档；[合同](../environment-ground-cache-contract.md) |
| [SimInventory](../../../scripts/sim/inventory_ledger.gd) | 容器内堆叠数量、预约、操作与受托责任 | 责任引用实物，不再存一份数量；不等于完整产权 |
| [SimArtifacts](../../../scripts/sim/artifacts.gd)、[SimClothing](../../../scripts/sim/clothing.gd)、实物方法记录 | 独特物件位置/来源、穿法/湿润、有限器物过程与阅读记录 | 不同时复制成普通数量库存，持有/看见/读过不等于学会 |
| [SimSocialMemory](../../../scripts/sim/social_memory.gd)、[SimInstitutionBook](../../../scripts/sim/institution_book.gd) | 本人有来源的认识/决定；机构任职和贡献记录 | 关系/礼遇/权限/实际履约分开；未实现通用ClaimBook/司法/继任 |
| 原action executor、服务、劳动/生产、交换等域 | 各自过程、阶段/成本/证据与原资源引用 | 统一请求是薄门面；新增搬运动作合同没有替换这些领域过程，尚无覆盖全部动作的生命周期/任意条件协商 |
| [SimConflicts](../../../scripts/sim/conflicts.gd)、[SimSparring](../../../scripts/sim/sparring.gd)、[SimHealth](../../../scripts/sim/health.gd) | 招式/弹障/成本、有限对练、真实伤源与恢复 | 使用原身体/qi/体力，不另造战斗人物；非完整致死/医疗/战争 |
| 日历/气候、weather、environment、local_heat、spirit_sources | 无状态历法曲线、晴雨相位、受体采样、固定参考局地热场、有限源与转换 | 热、五行亲和、qi、储热和灵源不合成万能数值；完整冷热/光/五相场仍待做 |
| [SimThermalHistory](../../../scripts/sim/thermal_history.gd)、[SimThermalSample](../../../scripts/sim/thermal_sample.gd)、[SimThermalSchema](../../../scripts/sim/thermal_schema.gd) | 来源派生覆盖、旧转换边界与历史采样分别校验；完整候选仍证明全部当前Q、原器物收支及冻结段 | 历史检查不读当前cells/flows，底量只由绑定气候与首次来源时刻推导；无新持久状态或回收，仍最多512活格 |
| [SimThermalCellStore](../../../scripts/sim/thermal_cell_store.gd)、SimLocalHeat | 唯一细格Q或孤立对称块的六轨道Q；派生流率执行原冻结段，源/设备/结构边界无损展开 | cells为只读临时投影，has_cell/cell_row/keys按需读取；原v3快照仍完整展开，无512扩容或性能改善承诺 |
| SimLocalHeat分配预检 | 脉冲/设备共用新格坐标并集与底量计划，容量先核再物化旧场；snapshot仅一份脱离行集 | allocation_capacity仅计逻辑格/实际槽/完全细化预留/流上界，不是字节保证；正式512、自定义绑定限额及原v3保持 |
| [SimGeographicClimate](../../../scripts/sim/geographic_climate.gd)、[ReolGeographicContent](../../../scripts/data/geographic_content.gd)、Main开局配置 | 新局地理草稿编译成原climate2曲线，隔离重建完整内容包/digest并校验后装配；默认草稿为world_geography.json | 只在创建时执行，无运行温度附加项或第二状态；普通Main只支持原时钟起点，恢复仅取档内曲线，不重编 |
| [SimLocalLight](../../../scripts/sim/local_light.gd)、[LocalLightRuntime](../../../scripts/runtime/local_light_runtime.gd) | 即时相对光读原热出流或固有发光器物ID索引，位置沿原承载者/地点查询；共用遮挡、叠加、当前视野纹理 | 索引派生只读不落档，无第二物品/光量/位置；动锚点旧时刻或欠算返回unknown；当前128源/441格，非移动热或完整光能账 |
| [SimSolarRules](../../../scripts/sim/solar_rules.gd)、[SimNaturalLight](../../../scripts/sim/natural_light.gd)、DayNight | 从已接受世界的climate2、原物理时刻/天气、屋顶事实派生太阳高度/昼长/自然光，普通界面与天色读取同源 | 无第二时钟/光量账/持久缓存；单地图宏观纬度；不是局部灯、完整感知或植物受光模型 |
| construction / workplaces / resting | 真实材料与结构、固定办事布局、床位/休息；完工/拆除先核原成本及整组塌顶余料，再预检热时刻，成功统一通知 | 围合、覆盖与功能可用性分开；拒绝保留实际工时/原物/结构，房间不发行贡献或资源 |
| [SimStructureQuery](../../../scripts/sim/structure_query.gd)、[ReolWallVisuals](../../../scripts/world/wall_visuals.gd) | 无状态投影原结构引用/覆盖格/层与独立物理事实，按四邻绘墙 | 不复制实体或写档；真实木墙门的视线不等于桌柜碰撞，成功施工通知经runtime使本地视野失效 |
| avian_life / soul_vessels / large_bodies | 雀身、残识与载体、3×3兽身的原持久状态 | 不是人类伪装副本；兽身不可选、无完整物种生成/繁衍 |
| field_opportunities / site_affairs / source_care | 地点、许可/核验、具名职责/个人线索与原过程引用 | 有限样本，不能当成通用任务/产权/组织平台 |

具体域的文件、过程及验证入口按[计划索引](../../plans/README.md)和[FEATURES](../../status/features.md)查；旧逐域实现细节见[整理前架构](../../archive/documentation_consolidation_20261104/docs/ARCHITECTURE.md)，其中当时的版本和待办只作历史。
