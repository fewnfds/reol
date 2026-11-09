# 环境、结算与事件的职责复核

2026-11-09，静态复核基点`388080210843e83aeae7efa130388d92b2cbc904`，分支`codex/world-events-plants`。范围为普通世界的装配、推进、事件、环境来源/响应、建筑拓扑、植物采样及存读目录；不代表全库逐行审计、运行复现或性能验收。本次仅修改文档；生产代码与既有测试证据保持原版本。

## 已核对的执行与所有权

| 代码证据 | 本次确认 |
|---|---|
| [SimSettlementKernel](../../scripts/sim/execution/settlement_kernel.gd)的`compile/begin/resume`及[SimWorldSettlement.initialize](../../scripts/sim/execution/world_settlement.gd) | 内核持调用图和游标，原域提交业务状态；环境、植物及事件处于同一有序执行图，没有各自独立的宿主更新循环 |
| [RegionalSimulation.advance_to_ms / _complete_boundary](../../scripts/sim/regional_simulation.gd) | 到期边界与预算续算共用整数毫秒；完整阶段结束才发布；当前并非全世界双缓冲同时读取上一步快照 |
| [SimEventQueue](../../scripts/sim/execution/event_queue.gd)及[SimWorldEvents](../../scripts/sim/world_events.gd) | 队列保存请求/回执，运输评估与植物觉醒调用原owner；持续生长不通过每毫秒事件重放 |
| [SimWorldEnvironmentFields](../../scripts/sim/world_environment_fields.gd)的`_configure_components/settle_at_ms/actual_at` | 温度和五行响应由原组件持有，来源缓存派生；人体和植物读取该域，尚无普通室内模型 |
| [SimWorldEnvironmentSourceParticipant](../../scripts/sim/world_environment_source_participant.gd)的`_prepare_transition` | 同源同位置未变时走无变化候选，真实变更才更新相关场/响应；植物更新没有另造一套五行场 |
| [SimWorldSaveDomains.registry](../../scripts/sim/world_save_domains.gd) | 事件、植物、环境均登记原通用存读管线，环境运行字段映射原wire key；不存在植物专用中央SL |

普通新局在`RegionalSimulation.initialize`创建`SimWorldEnvironmentFields`。源码中保留的`SimLocalHeat`旧模型及低层历史解析不构成当前普通世界的第二份环境所有者；也不能据此重新启用旧房温运行分支。

结论限于以上路径：没有发现需要再建结算内核、事件总线或统一世界状态库的依据。共同结构和局部字段相似不证明owner重复；具体业务算法仍需实现。

## 确认的接入缺口

以下是当前已声明的能力边界及扩域风险，不是新复现的运行回归。均归主计划第4阶段，维持原顶层领域。

1. **建筑拓扑尚未进入普通冷热/五行传播。** [SimConstruction._before_thermal_change / _after_thermal_change](../../scripts/sim/construction.gd)对当前环境域仅预检共同时间并返回；`SimWorldEnvironmentFields.MODEL`为`outdoor_fields_v1`。`thermal_barrier`事实存在不代表隔热已生效。房温应沿原环境入口扩展；房间分合承接原实际温度，并明确室内来源、室外输入及交换关系，防止同一来源在室外场和室内修正中重复计入。

2. **来源生命周期接缝尚非所有对象通用。** [SimWorldEnvironmentFields.replace_domain_source](../../scripts/sim/world_environment_fields.gd)只接受`plant:`；原器物及材料有各自已接适配。[SimWorldEnvironmentSourceParticipant._artifact_at](../../scripts/sim/world_environment_source_participant.gd)对`actor:`容器返回空源，因此携物不发源是当前范围，不能解释成已模拟了遮掩。后续复用原参与者及原包含关系，为真实消费者补校验、移动/消失和依赖失效，不简单解除前缀检查，也不另设一个全对象影响仓库。

3. **植物照度尚未消费人工光，查询时刻也需衔接。** [SimPlants.habitat](../../scripts/sim/plants.gd)读取`SimNaturalLight.at_cell`；[SimLocalLight.at_cell](../../scripts/sim/local_light.gd)已有自然/人工光组合，但其`_sources`要求`elapsed_ms == target_ms`，面向当前查询。直接替换调用会在分片快进中得到`pending_time`。第4阶段应复用原灯源、遮挡及光传播规则，提供明确时刻/阶段可用的模拟采样；显示照亮不自动证明植物生长条件已得到照度。`habitat`在实际温度查询失败时回退气候背景，也需在室内模型接入时明确失败处理，避免把未完成查询视作室温。

## 扩域前须守住的工程判断

- 环境模型扩展复用`GameClock`、`SimSettlementKernel`、`SimEventQueue`、`SimParticipationIndex`、原空间/建筑事实及`SimWorldSaveDomains`。执行顺序、动作受理和SL接口存在，不代表传播与受体算法已经实现。
- 一次事件可改变持续条件；条件归天气/环境等原域保存，队列仅负责相应离散工作。场景通知、离散请求和玩家消息分别使用已有接缝，避免把每次状态读取都变成事件。
- 房温平均不推广成整屋统一光照/五行；本项目已定的冷热等级抵消、五行max及独立灵气储量继续生效。室内外衔接、材料透过与分合权重须明确模型和误差，不能靠竞品例子自动决定。
- 同刻反馈遵循已有阶段与领域仲裁；确定顺序不等于公平，也不等于把所有反馈在零时间内迭代至稳定。确需局部求解时声明收敛与上限。
- 当前`SimWorldEnvironmentFields._refresh_targets`和来源`_prepare_transition`内部仍同步做完原子工作。已有合作预算不能抢占这些循环；扩展房间/移动源应测实际受影响工作和帧时，再沿原owner补有界续算，不把注册到期入口当成性能已解决。

一手来源与可借鉴/不可推出的结论已补入[既有研究](../../design/research/simulation_events.md)。领域边界写入[架构](../engineering/architecture/05-framework-domains.md)，交付范围仅更新[唯一主计划](../plans/foundation-priorities.md)，没有创建第二条开发计划或启动环境实现。

## 验证范围

`python tools/check_structure.py`检查330份当前文档、515份脚本，0错误，包含链接及活跃页16KiB上限检查；`git diff --check`通过。本轮不启动Godot、不查询CI，未新增运行/性能通过声明；游戏完整回归和停开证据仍见[事件/植物QA](20261109_world_events_plants.md)。
