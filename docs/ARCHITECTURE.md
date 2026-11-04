# 当前代码架构与边界

核对：2026-11-04。本文记录实际状态所有者和依赖，验收范围由[BASELINE](BASELINE.md)限定。未来完整引擎设计在[world_engine_program](plans/world_engine_program.md)，不把目标模块画成已完成系统。

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
| [WorldMapData](../scripts/sim/world_map_data.gd)、[NaturalEnvironment](../scripts/sim/natural_environment.gd) | 固定生成地形/原高度/静态通行；派生地表、植被覆盖、五行亲和与缓存 | 没有已验地表delta；亲和不是能量库存；覆盖不是完整独立植物 |
| [VillageSimulation](../scripts/sim/village_simulation.gd) | 人类原身体、唯一位置/朝向、原生活状态和村落配置 | 所属区是保存所有者，不是人物当前所在空间 |
| [RegionalSimulation](../scripts/sim/regional_simulation.gd) | 区域同步、域装配、共同边界/积压和跨域校验 | 现有固定域目录，非任意世界工厂/完整事件平台 |
| [SimLocalMotion](../scripts/sim/local_motion.gd)、[SimRouteTravel](../scripts/sim/route_travel.gd) | 手动/闪身及自动路段推进，读写同一身体 | 不复制位置、体力或时钟；显示插值不推进规则 |
| [SimEmbodiment](../scripts/sim/embodiment.gd) | 主体、载体居留、移动/行动/通信控制 | 居留不等于控制，控制通道不等于行动占用 |
| [SimInventory](../scripts/sim/inventory_ledger.gd) | 容器内堆叠数量、预约、操作与受托责任 | 责任引用实物，不再存一份数量；不等于完整产权 |
| [SimArtifacts](../scripts/sim/artifacts.gd)、[SimClothing](../scripts/sim/clothing.gd)、实物方法记录 | 独特物件位置/来源、穿法/湿润、有限器物过程与阅读记录 | 不同时复制成普通数量库存，持有/看见/读过不等于学会 |
| [SimSocialMemory](../scripts/sim/social_memory.gd)、[SimInstitutionBook](../scripts/sim/institution_book.gd) | 本人有来源的认识/决定；机构任职和贡献记录 | 关系/礼遇/权限/实际履约分开；未实现通用ClaimBook/司法/继任 |
| 原action executor、服务、劳动/生产、交换等域 | 各自过程、阶段/成本/证据与原资源引用 | 统一请求是薄门面，尚无通用动作生命周期/任意条件协商 |
| [SimConflicts](../scripts/sim/conflicts.gd)、[SimSparring](../scripts/sim/sparring.gd)、[SimHealth](../scripts/sim/health.gd) | 招式/弹障/成本、有限对练、真实伤源与恢复 | 使用原身体/qi/体力，不另造战斗人物；非完整致死/医疗/战争 |
| 日历/气候、weather、environment、local_heat、spirit_sources | 无状态历法曲线、晴雨相位、受体采样、局地余热、有限源与转换 | 热、五行亲和、qi、储热和灵源不合成万能数值；完整冷热/光/五相场仍待做 |
| construction / workplaces / resting | 真实材料与结构、固定办事布局、床位/休息 | 围合、覆盖与功能可用性分开；房间不发行贡献或资源 |
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

[WorldSessionSnapshot](../scripts/runtime/world_session_snapshot.gd)在共同时刻捕获联合快照，独立候选先恢复各域，再核跨域来源/成本/位置/占用；成功后才替换活世界与呈现引用。[SessionSaveSchema](../scripts/persistence/session_save_schema.gd)迁移版本，[SnapshotValues](../scripts/persistence/snapshot_values.gd)处理JSON值，[SimSaveStore](../scripts/persistence/save_store.gd)负责文件备份/原子替换。

历史没有的知识、交易、物件和经历不能由新开局补造；当前墙门/人物位置不能证明过去的见证。同毫秒次序只能用已有序号/半开区间证明，不声称完整历史重演。围合、占地索引、缓存和纹理可重建，不作为另一份存档真值。

ContentDB支持37份输入的独立内容包、旧v42兼容输入。根44另携`ReolWorldAssemblyInputs`的区域开局配置、区域设置和中心点；`WorldRestoreFactory`及`VillageSimulation.from_snapshot`沿原严格恢复/跨域校验构建候选，不运行新局物资、知识或机构记账。成功后再绑定原导航与呈现。覆盖/测试边界见BASELINE。

候选的配置/人员/地点不再借活区域；地图仍通过现有独立复制工厂取得固定生成器/显式测试地图，运行呈现仍限home/river。公开定义仍可写，时钟/动作/工作间/对练等部分规则仍直接读盘，任意开局/地图编辑和动态人物视图装配未完成。存档装配描述不是带运行历史的新局模板。

## 仍需建立的通用接缝

受控生成/稳定实体查询、数量批次与独特物的统一承载、持久平面地表改造、房间/导航局部失效、冷热/光/五相传播、动作生命周期、可组合能力/影响、独立世界工厂及创作工具、规模与历史索引。已有专用域必须沿这些接缝逐包迁移，不能为规划再造一套平行世界。
