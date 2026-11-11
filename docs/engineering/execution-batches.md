# 批计算与原状态提交

本合同属于共同运行与数据底座。交付顺序只在[主计划](../plans/foundation-priorities.md)，总体因果见[共同结算](settlement-contract.md)；本页说明当前CPU接入，不代表整个多核方案或规模性能通过。

## 任务、数据与所有权

[SimBatchExecution](../../scripts/sim/execution/batch_execution.gd)持有一次可回收任务，使用Godot `WorkerThreadPool.add_group_task()`。共享输入在提交前固定，每个chunk拥有私有输出和计时；worker只调整自身输出，不调整共享容器大小、不访问活SceneTree、不调用世界提供者、不写身体或库存。它不另持世界时钟、实体库或业务回执。

任务Callable只保留scratch `WorkGroup`，不反向保留handle、世界或场景。正常推进用`finish()`检查完成，未完成返回pending；完成后收集Godot任务资源，不立即阻塞主线程。`cancel()`撤销采用权，已运行的有界chunk可以结束；owner保留退休handle并在随后推进时收集。退出/世界替换负责最终回收，清理时可以等待。

线程完成顺序不决定游戏顺序。原owner检查时刻、代次、依赖及原对象，再按领域顺序提交；资源争用仍沿原预约/账本。计算结束不等于动作生效。

## 原身体连续推进

[VillageSimulation](../../scripts/sim/village_simulation.gd)选择当前到期人物，为[SimActorAdvance](../../scripts/sim/actor_advance.gd)准备需求固定点值/余数、有效速率、体力/恢复条件、旧锚点、目标时刻及已受理路段。稳定ID、动作ID和采用依据留在主线程；worker只读`PackedInt64Array`及`PackedVector2Array`。

计算包括饱食、精力、体力恢复及既有路段的位置/朝向，不包括工作选择、路线搜索、资源转移或攻击。串行和worker使用同一需求公式，巨大跨度先饱和再乘算，恢复沿同一余数；不建立另一套需求/运动规则。

普通`WorldContinuityRuntime._bind_navigation()`配置本接口。默认到期集合少于64人直接执行；较大集合按32人一个chunk、最多4个worker处理。无关身体不因跨格进入批次；`workers=0`用相同批数据串行计算，供对照。

采用时先完成相关身体的旧输入需求，再按稳定人物ID投影与通知。原执行器继续复核路径；路段已修复、取消或替换时不采用旧运动候选。`body_cell_crossed`/`body_space_changed`沿实际身体发出，行动、预约与取放效果仍归原owner。

有效受理路段只有在环境来源、可改变的库存认识、组合空间索引/观察者需要时才保留内部跨格步骤。全路几何证明仍有效且整条路无途中消费者时，`SimRouteTravel.Timeline`用绝对到达时刻直接求当前位置/朝向，原行动在权威读取或捕获时收敛path和当前段；到达及取放等后果仍由原执行器处理。此时表可丢弃，不存档，不拥有另一份身体状态，画面只读其已提交时间下的投影。

组合空间首次prepare用当前连续投影建索引并使既有身体到期重算，首次观察订阅也参与原边界修订，之后恢复精确维护；来源载体参与变化也重算到期。退出整路积分前先收敛已受理历史，再按新依赖处理未来。没有等价输入证明的独立Callables保留原细步。

需要精确跨格的身体也复用仍有效的全路几何证明，只计算当前过格/到达时刻；投影不会再次查询同版地形/阻挡。证明对象、路线引用或几何版本不匹配时恢复原通行复核/修路，而非把旧路径当作永久通行许可。

身体显式同步、动作/控制/几何依赖失效、重建和成功restore撤销准备结果；失败restore不改变活世界及有效候选。原anchor与时刻也须匹配，同ID的新身体不能继承旧结果。

## 共享空间读取与批量查询

[SimWorldGeometry](../../scripts/sim/world_geometry.gd)是原地图、建筑、植物及大型身体阻挡的可重建读取层，由`RegionalSimulation`持有，不保存另一份权威世界。普通人物和服务通过`bind_geometry_navigation()`直接使用模拟层路径/通行提供者；几何变化与原路线证明失效也在模拟层处理，`ReolWorld`转为读取适配。

读取按16×16格页组织，保存高度、地表类型、行走及掩体标记；稳定页复用，变化只替换已建页中受影响格，未知页首次需要时生成。植物生长状态不改变阻挡时不失效。`capture(area)`固定范围、来源ID和几何版本，封住页表并保留旧页；任务并行时owner可替换新页，既有输入仍可读，采用前用`is_current`核对。新世界/成功恢复会退休旧owner；旧页不写档，失败恢复不退休活输入。冷建块仍有同步成本，尚未移入后台。

`SimGridNavigation.Search.find_path`可在私有AStar上下文上运行同一算法。同步便利入口仍使用原主线程缓存；worker不得调用该全局缓存，也不得共享一个正在搜索的AStar。首批只验证了私有上下文批查询，尚未把普通行动的即时路线请求改为异步。

[SimBodyReadView](../../scripts/sim/body_read_view.gd)在原规则边界由owner同步所需地区并捕获身体ID、位置、高度列；worker不触发身体getter。它保留原地区/人物遍历顺序，当前每批捕获一次，尚未实现持久身体热列或显示发布。

[SimSpatialQueries](../../scripts/sim/execution/spatial_queries.gd)按64个身体分块，对多个线段求接触候选；达到4096个身体×线段候选对才尝试最多4个worker，小批用同算法串行。任务内一次解析列引用，避免每对候选重复访问共享脚本对象。候选按固定chunk顺序收敛，等距仍由原身体顺序决定。

真实消费者是`SimConflicts._advance_projectiles`：同边界捕获一次身体输入、批量查候选，再沿原投射物顺序核遮挡、收集全部接触、最后沿原规则提交伤害。此首批接入仍在原交锋回调内等待完成，没有跨帧交锋游标或新的取消时机；大批的等待也计入回调成本。不是每个领域独建线程或第二个战斗世界。

## 跨帧、存读与呈现

`RegionalSimulation`在边界开始前受理手动接管并执行一次手动移动，然后由原`SimSettlementKernel`的`native_interval/native_actors`步骤准备各地区批次。全部提交后检查完成；未完成返回宿主，原kernel保留游标，后续沿同一边界接续，手动位移不重放。

`has_pending_boundary()`读取同一个kernel的pending状态，涵盖native准备及后续阶段；`pending_boundary_ms()`读取其`at_ms`，不要求内部世界时间已经到达目标。地区提交后进入后续领域步骤，最终才发布`boundary_settled`及公共时间。等待期间外部命令和半步存档被拒绝，呈现保持最近完整状态；原owner的内部合法提交仍能完成。

人物采用本身也可让出：`VillageSimulation.NativeAdvance`保存一次已受理区间的需求采用、空间投影、既有动作、未来选择和观察游标，昂贵人物循环按小组检查宿主截止条件。所有到期身体的旧输入需求先完成，之后才允许空间通知观察同刻同伴；同刻人物仍按ID处理。`RegionalSimulation`记住已经完成的地区，不在下次resume重放。该游标只是原kernel步骤内的未完成工作，不是另一个时钟或保存状态。

存档只保存原身体、动作及共同时间。Packed输入/结果、线程handle、游标和计时不入档，不新增格式/迁移链。完整会话候选验证后替换世界、回收旧任务并重绑owner；坏候选不部分改活世界。

## 诊断与设备接缝

`actor_execution_work`有界记录准备/分配、提交、worker累计及时间跨度、排队、完成至收集延迟、原状态发布、采用/丢弃数和线程ID。输入提供者采样仍在主线程，发布包含原空间通知；worker数学耗时不等于整段身体推进成本。

普通诊断和人口压力报告包含各地区数据；`tools/stress_demo.py --actor-workers 0/4`对照相同路径。逻辑流速、帧P95/P99及真实渲染另行测量，线程ID/采用数只能证明接入。

环境GPU已经沿“紧凑输入、时刻/代次/依赖、候选输出、原owner采用”实际接入，继续复用。当前需求采用64位整数，不能改成浮点就假定同未来。身体批和空间候选本身没有GPU dispatch；普通环境的实际GPU采用和收益范围见[环境合同](world-environment-contract.md)与BASELINE。

当前仍有主线程输入采样、地区/动作决定、路线搜索、领域同步及发布；准备也不是可抢占回调。本接口不证明300人1×/60FPS或所有规则已多核，证据见[BASELINE](../status/baseline.md)。

旧`test_actor_advance`已随全量套件退役，原验证范围保留在QA。当前`tests/smoke.gd`短查身体串行/worker数值一致及取消标记，`spatial`补空间候选等距/过滤、保留旧页、局部地形变化及来源替换；完整世界采用、存读和长期稳定不由这个短检查证明。

官方依据：[WorkerThreadPool](https://docs.godotengine.org/en/4.7/classes/class_workerthreadpool.html)、[线程安全](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)。无新增依赖或业务autoload。
