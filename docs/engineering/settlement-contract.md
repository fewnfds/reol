# 共同模拟与结算内核

本合同贯穿[七个领域](architecture/05-framework-domains.md)。当前代码入口为[SimSettlementKernel](../../scripts/sim/execution/settlement_kernel.gd)、[SimWorldSettlement](../../scripts/sim/execution/world_settlement.gd)与`RegionalSimulation`；范围与证据分别见[技术总表](../status/technical-status.md)、[BASELINE](../status/baseline.md)。

## 引擎边界与所有权

Godot提供渲染、输入、SceneTree、固定物理步及碰撞服务。`_process`/`_physics_process`安排回调，不推导温度、五行、库存和伤势之间的业务关系。Reol的`GameClock`把宿主时间转为共同整数毫秒请求，`RegionalSimulation`持有目标、内部推进时间与已结算边界；渲染帧、物理帧和模拟时刻分别成立。普通50毫秒步可再按实际事件切分，不每毫秒扫描世界。

内核只持编译后的调用、依赖和未完成步骤。身体、器物、库存、伤势、环境响应、动作与随机状态仍归原owner；新概念须实际实现自己的规则。温度趋向目标、五行组合、材料预约或同时命中各有算法，不能用通用数值相加代替。

## 装配与依赖

`SimSettlementKernel`先接收固定阶段，再用`add_step(id, phase, callback, mode, after, before)`及`add_boundary(id, callback, runtime)`装配。`compile()`验证重复标识、未知依赖、跨阶段倒置和同阶段环；按阶段及依赖作稳定拓扑排序，无依赖平局按id排序。编译一次，运行期不重排图、不从场景树遍历实体，也不接受运行中追加规则。

`SimWorldSettlement`把当前原领域接入以下次序，保留原同毫秒行为：

1. `RegionalSimulation`先投影手动移动并推进有关地区；地区原生活决策仍在地区执行器内部。
2. `previous_interval`：环境场、健康、天气、衣着、常设劳动和计量劳动结清刚过去的区间。
3. `arrivals`及`environment_event`：行旅抵达与必要的原环境事务上下文。
4. `current_processes`：物品、服务、器物、修行、战斗、非人生命、建筑、家具、生产、休息及其余已接过程，按装配依赖提交。
5. `sampling`→`decisions`→`messages`→`transport`：野药条件、世界级未来选择、消息、运输评估/派遣。

`settlement.contract()`返回脱离内部引用的实际调用图；旧`schedule_contract()`保留公共分类目录，不能代替实际图。到期查询通过已注册原owner读取，地区、运输、消息和生态仍贡献相应边界；`SimParticipationIndex`负责域内活跃/到期/变脏候选。当前是边界驱动与固定步组合，不宣称全部旧领域已变成单一事件堆。

新领域先确定唯一状态owner、输入及生效时刻，在装配器注册到期入口、阶段与前后依赖，再接保存/恢复和必要呈现。仅新增同能力内容沿原定义扩展；新规则需代码实现。相互读取的领域不能用依赖环表达“瞬间互相计算”：有时间延迟就安排未来边界；确需局部平衡时由该owner实现有误差/收敛合同的求解。

当前装配仍是显式代码：调用图、`BOUNDARY_DOMAINS`、`SNAPSHOT_DOMAINS`、`ACTIVITY_DOMAINS`及对象查询各有不同职责。注册一个结算步骤不会自动获得身份、存读、占用或空间能力；扩域按[接入检查](architecture/05-framework-domains.md#新领域的接入检查)逐项核对。没有实际消费者的能力不强制注册，也不为统一表形状搬走原状态。

## 同刻效果、争用与变更

阶段顺序表达先后依赖，原领域负责同阶段的业务仲裁。稳定id只解决无依赖平局，不自动构成公平的资源分配规则。

| 类型 | 当前规则及原owner |
|---|---|
| 原材料/容器争用 | `SimInventory`的原预约与幂等事务；施工、家具和生产复核原物与操作位，不能各记一份剩余量 |
| 同刻命中与新决定 | `SimConflicts`先收集当前命中再提交；新动作线索先收集，后处理者不能偷看别人刚决定的起势 |
| 持续暴露与来源切换 | 环境先按旧条件结清区间，原物/来源候选在同一提交段成立；新条件影响后续响应，不改写过去 |
| 生成、移动、损毁/终止 | 原生命周期/建筑owner完成原状态与相关索引，发布变化；空间/环境读取同一原物，不在内核复制对象 |
| 随机结果 | 由原领域确定调用顺序并保存随机状态/结果；内核不抽签或每帧洗牌，显示刷新不取得新的业务随机结果 |

空间、来源和域内dirty通知沿已有明确接口，不向每个对象广播每次变化。`SimConstruction.space_changed`等领域内部通知仍随原状态提交同步更新相关索引，不能为了延迟画面而推迟内部因果。`RegionalSimulation.publish_action_finished()`在结算边界未完成时缓存结果；所有步骤结清后再发`action_finished`及`boundary_settled`，发布期间拒绝重入命令。新领域必须声明改变什么、哪些依赖失效及何时重评；注册依赖不会自动推导一套全知物理或权限系统。原事务仍负责候选/回执/失败原子性，内核不是对公开Dictionary直接写入的沙箱。

## 工作预算与未完成边界

`begin(from_ms, at_ms)`接受严格向前的有限区间；`resume(work_budget)`返回COMPLETE/PENDING/FAILED，游标只在步骤完成后前进。预算耗尽或YIELDING回调未完成会保留同一时刻/步骤；已完成领域不重算。失败与普通欠算区分，失败步骤不自动重试或继续依赖者。拓扑环在装配时拒绝，未完成步骤也不会在一次调用里无预算自旋。

普通回调可按时刻/无参数执行，CHECKED回调须返回bool；YIELDING的false表示保留当前步骤。BUDGETED回调接收`(at_ms, allowance)`并返回`Vector2i(实际工作量, Status)`，工作量须在1至allowance内。域持有自身活动项游标；每个实体不需要一条全局回调。`SimFacilityUse`已经按真实active工作逐项接入，过程中取消/替换的旧工作不借同一actor引用再次执行。

`advance_to_ms`保留原事件数预算，另接受工作预算。普通runtime每次执行器调用的默认工作预算为4096，快进预算不足继续原请求。一次原子回调本身不能被内核抢占；其他旧域的内部大循环及同步来源事务没有因此自动变成可续算，此边界须按实际热点逐域接入。

内部`elapsed_ms`可在部分阶段执行时到达边界时刻；`settled_ms()`只表示已完成边界。runtime保留原请求，阶段尚未完成时不发布新的`GameClock`时刻，不启动下一边界。沿该时钟发布的监听者看到完整世界与身体投影；共同对象/空间查询及已接入guard的行动入口拒绝半结算输入。`WorldContinuityRuntime.stop_player_action()`返回bool表示是否受理，相关UI依据真实回执更新提示；领域执行中允许内部中断，任意外部raw写不在保护范围内。视图比较起点与地区通知标记保留至完整提交，成功读档重置这些派生标记。

`CommittedWorldCanvas`只缓存最近完整世界边界的有限可见绘图参数，不复制世界状态；部分边界中的重绘回放旧投影，完成后才重新采集。`ConstructionRuntime`将结算中发生的视线障碍失效积存到公共`GameClock`发布后再通知呈现侧；Fog和灯光在部分边界保留dirty请求和上次投影，相关普通面板拒绝在此时刷新世界数据。这样领域内部索引可同步变化，外部视图不读取半结算结果；原始状态仍由各领域持有。

内核不是整步事务回滚器，失败前的领域效果已经写入原owner。`SimSettlementKernel.has_failed()`提供明确失败终态；runtime暂停并显示原因，后续不再续算失败内核。合法完整会话加载可恢复运行，不能将失败当普通PENDING等待。工作预算计数也不等于墙钟时间，地区前置推进及原子回调仍可能形成长帧。

## 保存、恢复与验收

游标和调用图是可重建的执行状态。部分阶段及失败边界不能捕获新存档，`RegionalSimulation.restore()`也拒绝原地恢复；结清后按根53/区域44保存原进行中动作和共同时间。完整会话`WorldContinuityRuntime.load_game()`是不同入口：拒绝同步推进回调中加载，帧间可独立校验合法旧档并替换整个世界、重绑owner和重置时钟欠算；不要求失败的旧世界先结清。坏候选不改活世界，不能留下指向旧身体/库存的调用。当前格式不新增游标存储库。

主要反例由`test_settlement_kernel`保护：依赖/平局、非法图、预算回执、失败停住及大量工作不丢不重。真实时钟/身体/存档边界由`test_clock_world_commit`保护，家具多工作项由`test_building_framework`保护；既有战斗、环境、库存测试仍是其业务规则owner。普通Main完整停开和声明负载按QA记录，不以局部调用计时保证整机规模。

## 采用的来源

[Godot 4.7处理入口](https://docs.godotengine.org/en/4.7/tutorials/scripting/idle_and_physics_processing.html)和[线程安全边界](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)说明宿主/物理步与活SceneTree的约束。[SimPy时间调度](https://simpy.readthedocs.io/en/stable/topical_guides/time_and_scheduling.html)提供到期及稳定同刻序的算法参考；[Factorio存读要求](https://www.factorio.com/blog/post/fff-270)说明停开不能改变后续结果，其[并行化经验](https://www.factorio.com/blog/post/fff-215)说明并行写入不自动提高性能。[RimWorld Multiplayer源码](https://github.com/rwmt/Multiplayer/blob/master/Source/Client/AsyncTime/AsyncTimeComp.cs)展示社区实现的固定调用与随机上下文，不是官方内部审计。这里只采用原理，未引入外部运行依赖或复制源码。
