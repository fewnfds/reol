# 当前代码架构与边界

核对：2026-11-05。本文记录实际状态所有者和依赖，验收范围由[BASELINE](BASELINE.md)限定。未来完整引擎设计在[world_engine_program](plans/world_engine_program.md)，不把目标模块画成已完成系统。

## 依赖方向

```text
main / 场景装配
  输入与UI → runtime命令适配 → sim规则/过程/状态
                ↓                 ↓
          世界/人物呈现       data定义与开局
                ↘ persistence快照/迁移/文件边界
```

纯模拟不依赖HUD或祖先节点路径。运行适配负责绑定/命令与投影，不另存身体、库存或社会余额。当前业务autoload为`GameClock`，第三方另有MCP helper；未创建全量EventBus/ECS/EntityRegistry/SaveManager。

## 状态所有权

| 领域/代码入口 | 权威状态或行为 | 边界 |
|---|---|---|
| [GameClock](../scripts/autoload/game_clock.gd) | 共同整数毫秒、暂停/倍速/等待、相位与帧欠算 | 分钟通知是投影，不是第二时间轴 |
| [WorldMapData](../scripts/sim/world_map_data.gd)、[NaturalEnvironment](../scripts/sim/natural_environment.gd) | 版本化底图加稀疏地表覆盖，通行读同一真值；派生地表/植被覆盖/五行亲和和缓存 | 均仍512；草稿/存读及暂停开发画笔已接，玩家合法改造待接；亲和不是能量库存，覆盖不是独立植物 |
| [SimTerrainEdits](../scripts/sim/terrain_edits.gd)、[TerrainEditorRuntime](../scripts/runtime/terrain_editor_runtime.gd) | 原地图上的小批量事务、空间预检；开发工具负责暂停准备和输入投影 | 显式启动才开放；沿原active/位置/施工材料引用，单笔最多256格，不发放玩家权限或平行状态 |
| [VillageSimulation](../scripts/sim/village_simulation.gd) | 人类原身体、唯一位置/朝向、原生活状态和村落配置 | 所属区是保存所有者，不是人物当前所在空间 |
| [RegionalSimulation](../scripts/sim/regional_simulation.gd) | 区域同步、域装配、共同边界/积压和跨域校验 | 现有固定域目录，非任意世界工厂/完整事件平台 |
| [SimLocalMotion](../scripts/sim/local_motion.gd)、[SimRouteTravel](../scripts/sim/route_travel.gd) | 手动/闪身及自动路段推进，读写同一身体 | 不复制位置、体力或时钟；显示插值不推进规则 |
| [SimMotionClearance](../scripts/sim/motion_clearance.gd) | 只读解析原过程当前首段及对角扫掠；固定运粮道路保守清场 | 不保存第二套位置/路线；施工新增阻挡和兽身清场复用，后续路线重规划仍待接 |
| [SimEmbodiment](../scripts/sim/embodiment.gd) | 主体、载体居留、移动/行动/通信控制 | 居留不等于控制，控制通道不等于行动占用 |
| [SimEntityQuery](../scripts/sim/entity_query.gd) | 无状态、只读地解析人物/雀身/独特器物/大型身体的原位置与记录所有者 | 不登记第二实体表、不推进时间；区域滞后和世界积压分别标明，不能直接作玩家所知 |
| [SimStorageQuery](../scripts/sim/storage_query.gd) | 无状态解析原区域/鸟域容器与数量条目；身体/地点/工程/鸟身提供原锚点 | 引用限定domain/region/container，数量多item；不生成实物、同步或赋予搬运权限 |
| [SimArtifactTransfers](../scripts/sim/artifact_transfers.gd) | 原独特器物归处的同步可拒绝预检与完整事务后通知 | world持有会话钩子、器物域公开；无库存/位置副本或持久事件，不是通用搬运或玩家知识 |
| [SimInventory](../scripts/sim/inventory_ledger.gd) | 容器内堆叠数量、预约、操作与受托责任 | 责任引用实物，不再存一份数量；不等于完整产权 |
| [SimArtifacts](../scripts/sim/artifacts.gd)、[SimClothing](../scripts/sim/clothing.gd)、实物方法记录 | 独特物件位置/来源、穿法/湿润、有限器物过程与阅读记录 | 不同时复制成普通数量库存，持有/看见/读过不等于学会 |
| [SimSocialMemory](../scripts/sim/social_memory.gd)、[SimInstitutionBook](../scripts/sim/institution_book.gd) | 本人有来源的认识/决定；机构任职和贡献记录 | 关系/礼遇/权限/实际履约分开；未实现通用ClaimBook/司法/继任 |
| 原action executor、服务、劳动/生产、交换等域 | 各自过程、阶段/成本/证据与原资源引用 | 统一请求是薄门面，尚无通用动作生命周期/任意条件协商 |
| [SimConflicts](../scripts/sim/conflicts.gd)、[SimSparring](../scripts/sim/sparring.gd)、[SimHealth](../scripts/sim/health.gd) | 招式/弹障/成本、有限对练、真实伤源与恢复 | 使用原身体/qi/体力，不另造战斗人物；非完整致死/医疗/战争 |
| 日历/气候、weather、environment、local_heat、spirit_sources | 无状态历法曲线、晴雨相位、受体采样、固定参考局地热场、有限源与转换 | 热、五行亲和、qi、储热和灵源不合成万能数值；完整冷热/光/五相场仍待做 |
| construction / workplaces / resting | 真实材料与结构、固定办事布局、床位/休息 | 围合、覆盖与功能可用性分开；房间不发行贡献或资源 |
| [SimStructureQuery](../scripts/sim/structure_query.gd)、[ReolWallVisuals](../scripts/world/wall_visuals.gd) | 无状态投影原结构引用/覆盖格/层与独立物理事实，按四邻绘墙 | 不复制实体或写档；真实木墙门的视线不等于桌柜碰撞，成功施工通知经runtime使本地视野失效 |
| avian_life / soul_vessels / large_bodies | 雀身、残识与载体、3×3兽身的原持久状态 | 不是人类伪装副本；兽身不可选、无完整物种生成/繁衍 |
| field_opportunities / site_affairs / source_care | 地点、许可/核验、具名职责/个人线索与原过程引用 | 有限样本，不能当成通用任务/产权/组织平台 |

具体域的文件、过程及验证入口按[计划索引](plans/README.md)和[FEATURES](FEATURES.md)查；旧逐域实现细节见[整理前架构](archive/documentation_consolidation_20261104/docs/ARCHITECTURE.md)，其中当时的版本和待办只作历史。

## 时间、空间与行动

- 模拟依共同整数毫秒和有名边界推进，分钟需求用保存的固定点余数。预算耗尽保留target/欠算，不丢时间；`_process`只呈现。
- 跨区写入前同步有关区域，近远区共享原事实与规则。安静区间可批算，战斗/环境等已接细步不能冒称全部事件化远区完成。
- 同刻先结旧区间和既有过程，再形成未来决定；冲突先收集线索/命中再提交，后处理者不提前看见别人刚决定的起势。
- 身体有唯一连续位置，格路/地块用于通行和放置。多格身体检完整覆盖及扫掠；动态通行组合静态地图、真实墙门和兽身，不把视图瓦片当碰撞真值。
- `owns_for_scope`只读各域原占用，不是新增锁镜像；动作可占不同控制/执行通道，不能强行把所有生命压成一条全局动作轨。
- 新引擎先平面地块，旧档高度/飞行仍按历史恢复；本轮没有抹平旧地图或新增高差系统。

## 输入、认识与呈现

输入提交意图，领域在实际开工/完成前复核原条件。界面只显示本人已知/眼前可见投影，诊断可全知但不写入角色记忆。接收者理解、意愿、能力、资源、控制与真实结果各自成立；未来AI只是表达/计划入口，不能绕过规则。

`HumanoidPose`读取原身体和过程；共享外观采样与分层不拥有物品或业务状态。八方向合同保持解剖左右，当前像素技术样本不代表所有体型/服装/动作已完成。绘图持有同一次观察的会话引用，调试器重入读档时不能混用两代世界。

## 存读提交边界

兼容方向见[当前版本与历史退役](COMPATIBILITY.md)：只维护一套当前运行模型/写档格式，历史输入仅在明确范围内转换后进入当前模型。本节记录代码实际存在的入口，不为多代迁移或旧生成器提供永久保留承诺。R0a已删除区域直读中永远达不到当前格式的30–37转换路径，旧根档导入和旧地图支持范围未改。

[WorldSessionSnapshot](../scripts/runtime/world_session_snapshot.gd)在共同时刻捕获联合快照，独立候选先恢复各域，再核跨域来源/成本/位置/占用；成功后才替换活世界与呈现引用。[SessionSaveSchema](../scripts/persistence/session_save_schema.gd)迁移版本，[SnapshotValues](../scripts/persistence/snapshot_values.gd)处理JSON值，[SimSaveStore](../scripts/persistence/save_store.gd)负责文件备份/原子替换。

[LegacyRegionalUpgrades](../scripts/persistence/legacy_regional_upgrades.gd)只持有根迁移仍需的九个历史形状纯转换，按需载入，不拥有世界实例、时间或执行器。普通`RegionalSimulation.restore`只接受当前区域41；旧39/40仅在原有限热导入器的独立候选入口接受并复验，不能直接替换已初始化世界。根迁移后的内容与在途事实仍由同一当前候选验证；没有复制一个可推进的历史模拟器，也没有新写档格式。清点与后续退役条件见[首包清单](plans/compatibility_retirement.md)。

历史没有的知识、交易、物件和经历不能由新开局补造；当前墙门/人物位置不能证明过去的见证。同毫秒次序只能用已有序号/半开区间证明，不声称完整历史重演。围合、占地索引、缓存和纹理可重建，不作为另一份存档真值。

ContentDB支持37份输入的独立内容包、旧v42兼容输入。根44另携`ReolWorldAssemblyInputs`的区域开局配置、区域设置和中心点；`WorldRestoreFactory`及`VillageSimulation.from_snapshot`沿原严格恢复/跨域校验构建候选，不运行新局物资、知识或机构记账。成功后再绑定原导航与呈现。覆盖/测试边界见BASELINE。

候选的配置/人员/地点/底图都不借活世界。地图由存档描述与宿主`restore_map_factory`构造，普通游戏使用严格的`WorldMapData.from_descriptor`，合成测试地图显式注入独立工厂；工厂不是存档可执行内容。旧`reol_noise` v1冻结原tuple，新`reol_flat_noise` v1按受限seed生成、有效格高度0，尺寸仍512。根45才允许新生成器，旧1–44不能靠改版本标签接受新地图。

普通新局从`data/scenarios/world_generation.json`读取平面地图描述；`main.configure_opening_map`只允许未入树的新场景接受独立地图草稿，不能改运行世界。存档按自己的实例描述恢复，旧丘陵不追改。运行呈现仍限home/river；home视图在接受后按原人物名单增删并更新选择列表，不生成新身体。公开定义仍可写，时钟/动作/工作间/对练等部分规则仍直接读盘，任意开局/地图编辑尚未完成。存档装配描述不是带运行历史的新局模板。

B0a在原地图上增加`[x,y,terrain]`稀疏覆盖，flat支持草/水/岩及还原基底，legacy拒非空覆盖。根46保存覆盖；45及更早按原格式迁入空覆盖，46缺字段拒绝。联合/单域均先在独立地图恢复覆盖，再验证身体/结构/剩余路径，失败不替换活世界。水变化按会话探测距离使邻近自然属性失效；原瓦片以256格帧预算重绘，先清旧植被，未加载格后续直接读真值；静止视线也置dirty。地图低层API不承担玩家权限/物资/在途冲突，不可直接暴露为玩家免费改地。当前范围与待验见BASELINE。

B1a继续沿原`SimConstruction`和`SimWorkplaces`读结构，不另建通用实体表。`structures_changed(cells)`只在真实完工/门操作/拆除及连带塌顶结算、索引和人员释放后发布；候选恢复不造施工事件。`ReolWorld`的视线来源与通行来源独立，重绑来源触发全视野失效，有限改变格仅触及当前视域时更新。新查询路径读最新阻塞；既有过程仍在下一步检查，完整在途路线响应尚未统一，不能称任意世界导航已完成。单工地/单格工程和固定值事房模板限制仍保留。

主场景首次探索在全部开局结构来源装配后运行，已有探索在普通加载时保持。施工绘制/选项随visibility_updated刷新，即使暂停也更新；四邻墙形在读取邻格当前状态前过滤实际可见性，未见连接暂省略，不借全知查询泄露墙后变化。

B1b将当前在途首段（含对角旁格）统一为原过程只读查询，玩家journey通过runtime补入。建墙/建关闭门/关门在原物理提交前保护这些段，保留工时/材料及行走，不调换共同毫秒结算顺序；低床/屋面不使用新增阻挡的运动守卫，真实占地仍检查。兽身占地也读同一查询，去掉终态服务全表扫描。固定运粮目前不依新墙重规划，所以建成阻挡保守避让其道路；这是待退役限制，非永久道路特权，也不是完整封路绕行。

大型身体查询沿原large_bodies域，`footprint`表示格尺寸、`swept_bounds_cells`直接读原保守占用、`physical_bounds_px`只表示连续中心对应的像素呈现/接触范围。三者不混为第二导航状态；记录所属地区也不推断空间包含。查询不返回未来路线/目的地，不同步滞后或消耗欠算预算；不是通用受控生成/移除接口。

热场纯投影显式分成功数值与不支持原因，失败没有数值字段。人体未来预判用`heat_supported/heat_reason`标明不确定，仅提供有界温度范围与定性说明，不制造精确温度或负担；穿衣/暖身意图在真实执行时重验。药草实际采样/候选校验不接受失败投影，不按零继续。当前热场支持正负局部温差，固定冷热器物已接入；移动源与稀疏回收仍未实现。

C1a-0此前将根/区域/器物格式推进47/39/7：成功释热事件带实际`heat_amount`，与原热收据的行动、原物、本人、时刻、格坐标和金额互核；失败与取消事件不得带该字段。候选先初始化同一热域以提供存档绑定规则，再恢复器物，等结构和来源恢复后严格恢复热状态，不借活场。区域38/器物6的机械导入只从已有收据补金额，原热定义/账/冻结流/样本及内容digest都不变；无配对事件或夹带未来字段拒绝。原完成扣charge路径保持，未新增所有历史charge前后账，不能将金额互核等同完整历史资源审计。

当前C1b-1写根49/区域41/器物8，热定义及状态3；村落7、人体环境3、土地资源4、药草生态状态2不变。`SimLocalHeat`持有固定参考 `-10000` 下的非负整数Q，先除容量再减背景以避免负温差取整错误。分配背景底量与后续外界流入计`ambient_in`，外界流出计`loss_energy`，旧脉冲来源独立计`input_energy`；持续放热计`continuous_input`，吸入原器物计`absorbed_energy`。守恒为 `sum(Q)+loss_energy+absorbed_energy=input_energy+continuous_input+ambient_in`。室外变化只改边界，不直接重设Q；当前最多保留512活跃格，满额明确拒绝新patch，无自动回收。

[SimThermalReclaimProbe](../scripts/sim/thermal_reclaim_probe.gd)仅为显式开发检查：按逻辑记录/覆盖格访问预算读取同一原热场及来源、历史样本、在途动作，返回脱离原状态且排序的诊断。预算不足无部分结果；`complete`仅表示扫描完成，积压或待源位置未知仍是`status=unknown`，`can_reclaim`始终false。气候包络查询独立合并日/季曲线和可达天气偏移的保守极值，不是误差保证或未来天气预报；自定义背景Callable不执行。此接缝不保存另一份Q、不接玩家UI、不删除格或改变求解器，后续生命周期/聚合仍待实现。

`SimThermalSchema`验证来源覆盖、分配底量、当前守恒、逆推原冻结段及绝对/旧偏量两种样本，并与原器物余额/启停事件互核。`ThermalImport`先用只读`LegacyHeatV1/V2`在独立旧候选核验原内容/结构/热账/受体，再构造完整当前候选；旧输入不会成为活运行域。v1在保存时刻转换Q，v2保留原Q/账/样本、只补空设备账和可证冻结终点；不从磁盘补新器物。原样本按`legacy_excess`保留，`legacy_limits`仅记录原档可证明的边界，不伪造过去绝对物理。具体支持范围见[兼容政策](COMPATIBILITY.md)。

区域和runtime在身体/旅途前预检热场下一冻结段的数值预算。失败保留目标和未处理时间，不扣该段资源；GameClock可已记入期望时间及帧积压，不能声称全局所有时间都未变化。期望时钟与物理时刻不等时，普通save_game在任何文件写入前ERR_BUSY，保护原主档/备份；当前格式不承诺保存未结算时间。移动源仍未接通。

C1a-3在每次冻结流与边界查询内对默认气候地区复用一次背景/下一边界，不保留跨次缓存。温度和边界Callable分别保留逐格语义；候选以自己的传入anchor/segment重建，不借活时刻。该优化不改变Q、时序、版本或512格上限；性能及相同未来证据只见BASELINE。

C1a-4的`set_geometry(roofed, barrier, reuse_within_pass=false)`仅在调用方承诺一轮同步计算中几何稳定时，按格复用该轮导热查询；当前装配/当前候选绑定原`SimConstruction`时显式启用，旧导入器仍用两参。缓存为`_candidate_flows`局部变量，不跨重冻/拓扑/时间/候选存留，不写档。自定义背景Callable强制走原路径，以保留可能改变几何的回调顺序；普通自定义几何默认也不复用，省略第三参重绑即恢复原调用行为。冷热流、整数顺序及能量合同不变。

C1b的[SimThermalTransferBudget](../scripts/sim/thermal_transfer_budget.gd)是无状态的共同转移核。有限端口分别限制旧出量和旧入容量，空端口仅是外界；`span`保持原速率并求最早整毫秒耗尽边界，`freeze`才在不足一毫秒时按比例/稳定余数分配，再双端取小并保守补余，明确不承诺最大吞吐。整数乘除不构造大乘积，0流不制造成本。无启用设备时走可信`field_span`，有设备时邻边/外界/器物端口共同进入预算；累计数值上限仍走原失败/积压合同。

固定冷热器物的`stored_q/enabled/region/container`只归`SimArtifacts.objects`，热域只存累计分源账。火石扣储量、寒石填容量，同格净温差为零仍各自记真实转移。普通开局默认关闭；本人研究后启用需原动作一分钟及1灵气，关闭需一分钟但不要求本人学过启用。启用中禁止取放/交割；耗尽或吸满不自动改开关。切换先在原共同边界纯预检，再无yield地提交原物开关、热凭据、原动作事件；失败还原原开关。热场持久保存`segment_until_ms`，部分积分后不能用新余额延长旧冻结段。灵气基线把付费enable纳入原账，不新增另一份人物资源。

A1b-0容器归处先支持原区域人物/地点、工程材料的carrier/material_cell，以及鸟域的bird/site。`locate`返回原库存及位置owner/time、carrier、stale与积压，`item`只追加entry_present/quantity/available/entrusted。数量引用不是实例ID，原账零项与不存在项明确区分；当前数量账无统一物品目录，不伪造目录限制。工程材料在project库存里随人移动，中断仍在同一库存、位置转material_cell；空容器有锚点不表示有材料。鸟货物只在鸟域账本，位置沿鸟身，不复制成人物库存。原器物的非野外位置查询也复用同一容器接缝，野外slot继续归field域。

这些查询用于规则/编辑调试，不能直接作玩家有限所知，也不能旁路原取放/预约/权限。原位置时刻较旧时不自动结算。当前只支持上述已证明的锚点；自然resource虚拟账、在途货运/嵌套箱等未接时明确unsupported，不推断原点/人物或精确运动。无新增持久状态/格式；受控生成、可搬容器及跨格预检仍待后包。

A1b-1的`world.artifact_transfers`（也由`artifacts.transfers`公开）只覆盖take/place/draw及私人完整交割。`set_guard`安装受信任的纯同步检查，布尔true允许、false/非布尔/失效非空Callable拒绝，空Callable恢复默认；检查中不允许器物begin/begin_draw/cancel和私人request/cancel重入，但它不是任意脚本沙箱。候选载荷含原独特器物引用、from/to限定归处、共同at_ms和原action/cause，守卫传副本；通知及entity/from/to嵌套引用均只读，监听者需修改时先duplicate，避免同一signal前后监听者互相污染。拒绝终止原到期动作但不回滚已付时间/qi；成功`committed`仅在原物、事件、active释放，以及私交割的钱/收据/工作终态全部提交之后发一次。draw报告被引物而非施术环。world原位restore保留钩子，独立候选各自持有且恢复不补发事件；整world替换时由装配重绑。无新存档字段/版本，不连接真实持续热结算，不能在事后signal里倒推旧位置结热；native/施工/鸟域通知尚未接。

## 仍需建立的通用接缝

空间目标见[组合空间合同](../design/systems/construction_and_space.md)：地块承载可跨格的实体，区域指定与推导房间分开。现有多格兽身不等于通用多格家具/植物已接，单格药源也不是未来药田模型；区域种植与通用放置仍待实现。

受控生成/稳定实体查询、数量批次与独特物的统一承载、玩家合法改地动作、房间/导航局部失效、冷热/光/五相传播、动作生命周期、可组合能力/影响、独立世界工厂及完整创作工具、规模与历史索引。已有专用域必须沿这些接缝逐包迁移，不能为规划再造一套平行世界。
