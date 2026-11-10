# 共同模拟与结算内核

> 实现参考：描述代码接口及消费者假设，可随重构更新；稳定边界见constraints，范围按当前用户任务。

本合同贯穿[七个领域](architecture/05-framework-domains.md)。当前代码入口为[SimSettlementKernel](../../scripts/sim/execution/settlement_kernel.gd)、[SimWorldSettlement](../../scripts/sim/execution/world_settlement.gd)与`RegionalSimulation`；范围与证据分别见[功能范围](../status/features.md)、[BASELINE](../status/baseline.md)。

## 引擎边界与所有权

Godot提供渲染、输入、SceneTree、固定物理步及碰撞服务。`_process`/`_physics_process`安排回调，不推导温度、五行、库存和伤势之间的业务关系。Reol的`GameClock`把宿主时间转为共同整数毫秒请求，`RegionalSimulation`持有目标、内部推进时间与已结算边界；渲染帧、物理帧和模拟时刻分别成立。普通50毫秒步可再按实际事件切分，不每毫秒扫描世界。

过载时统一降速与有限新时间准入由`GameClock`及`ReolSimulationPacing`负责，完整政策、宿主预算和显示合同见[运行流速](simulation-pacing.md)。它不改变本页的阶段、事件时刻或原所有者；主动放慢期间未接纳的现实时间不是模拟欠算。

内核只持编译后的调用、依赖和未完成步骤。身体、器物、库存、伤势、环境响应、动作与随机状态仍归原owner；新概念须实际实现自己的规则。温度趋向目标、五行组合、材料预约或同时命中各有算法，不能用通用数值相加代替。

## 装配与依赖

`SimSettlementKernel`先接收固定阶段，再用`add_step(id, phase, callback, mode, after, before, condition)`及`add_boundary(id, callback, runtime)`装配。`compile()`验证重复标识、未知依赖、跨阶段倒置和同阶段环；按阶段及依赖作稳定拓扑排序，无依赖平局按id排序。编译一次，运行期不重排图、不从场景树遍历实体，也不接受运行中追加规则。

装配器将可直接绑定的调用编译到当前原owner；恢复或替换领域后重建调用图，不把旧内核带到新世界。可选`condition(at_ms)`由原owner声明是否有结算工作，须为无副作用的bool查询；无条件入口保留原执行。衣着/器物/工作台等只在实际过程存在时执行，决定交接按原待办触发；持续需求/来源/身体恢复等不因空行动而停算。

条件在轮到该步骤时求值，先前阶段可以唤醒后续领域。条件为false跳过业务回调，依赖次序仍保留；开始过的YIELDING/BUDGETED步骤在续算时不重新用条件筛掉，以完成原游标与清理。跳过不消耗业务工作额度，宿主截止检查仍有效；条件失效或返回非bool为失败。`executed_steps`/`skipped_steps`只作累计诊断，不持业务事实或入档。

承担公共清理的步骤保留执行：`object_lifecycle`完成后释放本边界的环境事务上下文，即使先前步骤取消了最后一个到期物品动作也不能跳过。`has_settlement_work()`只决定是否准备该环境上下文，不代替清理合同。

`SimWorldSettlement`把当前原领域接入以下次序，保留原同毫秒行为：

1. `RegionalSimulation`先受理手动接管并投影一次手动移动；原kernel的`native_interval/native_actors`准备身体批计算，完成后按序提交并推进地区。待计算沿同一kernel续算，地区生活决策仍在原执行器内部，详见[批执行](execution-batches.md)。
2. `previous_interval`：环境场、健康、天气、衣着、常设劳动、计量劳动和到期植物结清刚过去的区间。
3. `arrivals`及`environment_event`：行旅抵达与必要的原环境事务上下文。
4. `current_processes`：植物动作、物品、服务、器物、修行、战斗、非人生命、建筑、家具、生产、休息及其余已接过程，按装配依赖提交。
5. `sampling`→`decisions`→`messages`→`events` → `transport`：野药条件、世界级未来选择、消息、运输评估/派遣。

`settlement.contract()`返回脱离内部引用的实际调用图；旧`schedule_contract()`保留公共分类目录，不能代替实际图。到期查询通过已注册原owner读取，地区、运输、消息和生态仍贡献相应边界；`SimParticipationIndex`负责域内活跃/到期/变脏候选。当前是边界驱动与固定步组合，不宣称全部旧领域已变成单一事件堆。

新领域先确定唯一状态owner、输入及生效时刻，在装配器注册到期入口、阶段与前后依赖，再接保存/恢复和必要呈现。仅新增同能力内容沿原定义扩展；新规则需代码实现。相互读取的领域不能用依赖环表达“瞬间互相计算”：有时间延迟就安排未来边界；确需局部平衡时由该owner实现有误差/收敛合同的求解。

### 局部移动与世界后果

普通Main为原生行动开启`native_route_events_enabled`。`VillageSimulation.next_boundary_ms()`仍逐一处理过格、路段抵达、库存观察和原空间通知；`next_world_boundary_ms()`仅将具有完整通行证明的路线的最终抵达/超时，以及其他真实行动后果贡献给世界。两个截止点使用同一个`SimParticipationIndex`的不同kind，原行动、原身体和共同时间不变。`native_actors`仍可按宿主预算挂起，不把整批移动变成长原子回调。

`SimActionExecutor`在实际找到/修好完整路线后登记可重建的完成时刻与经过格（含斜角两侧），该证明不落档。控制资格仍按原owner复核；几何版本单独读取。明确地形/结构/兽身占地区域改变时，只有不相交的旧证明可更新版本；未知范围、相交、传送或替换路线保留细边界直到重规划/新行动，不能凭当前第一段通畅就接受整条旧路。读档重绑后未重新证明的在途路线也走保守路径。

植物成熟、产物或休眠不自动代表通行变化；适配器比较实际阻挡格。大型身体使用原扫掠占地的前后范围，起步/结束扫掠即使中心未换格仍会失效。远区有局部移动到期或世界后果到期时都要执行/刷新截止点，避免保留一个已经过期的远区世界边界。

局部源的过格通知保留实际毫秒，环境owner按这些时刻依次接续；抵达取放、需求改变、攻击/飞行物、天气、环境响应等本来的世界边界继续分割区间。该优化只覆盖已有通行/通知接缝的原生路线，不宣称全部领域已变成可任意合并的事件。

原生行动可能在世界区间尚未结清时完成，完成通知的`finished_ms/world_time_ms`取原生owner的实际效果时刻；不能取尚未推进的`world.elapsed_ms`。通知仍积存到完整世界提交后发布。

当前装配仍是显式代码：调用图、`BOUNDARY_DOMAINS`、`SimWorldSaveDomains`、`ACTIVITY_DOMAINS`及对象查询各有不同职责。注册一个结算步骤不会自动获得身份、存读、占用或空间能力；扩域按[接入检查](architecture/05-framework-domains.md#新能力接入需回答)逐项核对。没有实际消费者的能力不强制注册，也不为统一表形状搬走原状态。

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

`begin(from_ms, at_ms)`接受严格向前的有限区间；`resume(work_budget, should_yield)`返回COMPLETE/PENDING/FAILED，游标只在步骤完成后前进。预算耗尽或YIELDING回调未完成会保留同一时刻/步骤；已完成领域不重算。失败与普通欠算区分，失败步骤不自动重试或继续依赖者。拓扑环在装配时拒绝，未完成步骤也不会在一次调用里无预算自旋。

普通回调可按时刻/无参数执行，CHECKED回调须返回bool；YIELDING的false表示保留当前步骤。BUDGETED回调接收`(at_ms, allowance)`并返回`Vector2i(实际工作量, Status)`，工作量须在1至allowance内。域持有自身活动项游标；每个实体不需要一条全局回调。`should_yield_work()`只在当前resume执行期间提供同一个宿主截止条件，允许装配器传给域，在其内部工作项间让步；不进入业务时刻或存档。环境到期响应、`SimFacilityUse`、植物due项和离散事件已接入，过程中取消/替换的旧工作不借同一actor引用再次执行。

`advance_to_ms`保留原事件数预算，另接受工作预算。普通runtime每次执行器调用的默认工作预算为4096，快进预算不足继续原请求。一次原子回调本身不能被内核抢占。环境移动来源、设备耗尽与临时源到期直接续算原`SimEnvironmentSourceChange`候选，按场工作量和响应格数让步；不发布中间结果、不重跑已采用来源，取消仍由原候选释放。外部物品命令的准备/同步提交和其他旧域内部大循环没有自动变成可续算，此边界须按实际热点逐域接入。

内部`elapsed_ms`可在部分阶段执行时到达边界时刻；`settled_ms()`只表示已完成边界。`has_pending_boundary()`涵盖native准备及kernel阶段，`pending_boundary_ms()`给出准确目标。runtime保留原请求，阶段尚未完成时不发布新的`GameClock`时刻，不启动下一边界。沿该时钟发布的监听者看到完整世界与身体投影；共同对象/空间查询及已接入guard的行动入口拒绝半结算输入。`WorldContinuityRuntime.stop_player_action()`返回bool表示是否受理，相关UI依据真实回执更新提示；领域执行中允许内部中断，任意外部raw写不在保护范围内。视图比较起点与地区通知标记保留至完整提交，成功读档重置这些派生标记。

`CommittedWorldCanvas`只缓存最近完整世界边界的有限可见绘图参数，不复制世界状态；在完整公共时钟发布时同步采集，开始下一边界前即持有最新投影；暂停中的合法呈现变化也同步采集。延后的`_draw()`只回放缓存，部分边界不读取世界。`ConstructionRuntime`将结算中发生的视线障碍失效积存到公共`GameClock`发布后再通知呈现侧；Fog和灯光在部分边界保留dirty请求和上次投影，相关普通面板拒绝在此时刷新世界数据，命令受理/拒绝提示独立更新，终态失败也不会吞掉回执。这样领域内部索引可同步变化，外部视图不读取半结算结果；原始状态仍由各领域持有。

内核不是整步事务回滚器，失败前的领域效果已经写入原owner。`SimSettlementKernel.has_failed()`提供明确失败终态；runtime暂停并显示原因，后续不再续算失败内核。合法完整会话加载可恢复运行，不能将失败当普通PENDING等待。工作预算计数也不等于墙钟时间，地区前置推进及原子回调仍可能形成长帧。

## 保存、恢复与验收

游标和调用图是可重建的执行状态。部分阶段及失败边界不能捕获新存档，`RegionalSimulation.restore()`也拒绝原地恢复；结清后按[当前格式](../status/baseline.md)保存原进行中动作和共同时间。完整会话`WorldContinuityRuntime.load_game()`是不同入口：拒绝同步推进回调中加载，帧间可独立校验合法旧档并替换整个世界、重绑owner和重置时钟欠算；不要求失败的旧世界先结清。坏候选不改活世界，不能留下指向旧身体/库存的调用。当前格式不新增游标存储库。

主要反例由`test_settlement_kernel`保护：依赖/平局、非法图、预算回执、失败停住及大量工作不丢不重。真实时钟/身体/存档边界由`test_clock_world_commit`保护，家具多工作项由`test_building_framework`保护；既有战斗、环境、库存测试仍是其业务规则owner。普通Main完整停开和声明负载按QA记录，不以局部调用计时保证整机规模。

## 采用的来源

[Godot 4.7处理入口](https://docs.godotengine.org/en/4.7/tutorials/scripting/idle_and_physics_processing.html)和[线程安全边界](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)说明宿主/物理步与活SceneTree的约束。[SimPy时间调度](https://simpy.readthedocs.io/en/stable/topical_guides/time_and_scheduling.html)提供到期及稳定同刻序的算法参考；[Factorio存读要求](https://www.factorio.com/blog/post/fff-270)说明停开不能改变后续结果，其[并行化经验](https://www.factorio.com/blog/post/fff-215)说明并行写入不自动提高性能。[RimWorld Multiplayer源码](https://github.com/rwmt/Multiplayer/blob/master/Source/Client/AsyncTime/AsyncTimeComp.cs)展示社区实现的固定调用与随机上下文，不是官方内部审计。这里只采用原理，未引入外部运行依赖或复制源码。

全局离散工作在 messages 后、transport 前由 `SimEventQueue` 有界派发；可信规则目录为 `SimWorldEvents`。连续区间过程仍归原域，详见[事件合同](event-contract.md)。
