# 批计算与原状态提交

> 实现参考：描述代码接口及消费者假设，可随重构更新；稳定边界见constraints，范围按当前用户任务。

本合同属于共同运行与数据底座。施工出口只在[主计划](../plans/foundation-priorities.md)，总体因果见[共同结算](settlement-contract.md)；本页说明当前CPU接入，不代表整个A包或规模性能通过。

## 任务、数据与所有权

[SimBatchExecution](../../scripts/sim/execution/batch_execution.gd)持有一次可回收任务，使用Godot `WorkerThreadPool.add_group_task()`。每个chunk私有输入、输出和计时；容器先完成分配，worker不调整共享容器大小、不访问活SceneTree、不调用世界提供者、不写身体或库存。它不另持世界时钟、实体库或业务回执。

任务Callable只保留scratch `WorkGroup`，不反向保留handle、世界或场景。正常推进用`finish()`检查完成，未完成返回pending；完成后收集Godot任务资源，不立即阻塞主线程。`cancel()`撤销采用权，已运行的有界chunk可以结束；owner保留退休handle并在随后推进时收集。退出/世界替换负责最终回收，清理时可以等待。

线程完成顺序不决定游戏顺序。原owner检查时刻、代次、依赖及原对象，再按领域顺序提交；资源争用仍沿原预约/账本。计算结束不等于动作生效。

## 原身体连续推进

[VillageSimulation](../../scripts/sim/village_simulation.gd)选择当前到期人物，为[SimActorAdvance](../../scripts/sim/actor_advance.gd)准备需求固定点值/余数、有效速率、体力/恢复条件、旧锚点、目标时刻及已受理路段。稳定ID、动作ID和采用依据留在主线程；worker只读`PackedInt64Array`及`PackedVector2Array`。

计算包括饱食、精力、体力恢复及既有路段的位置/朝向，不包括工作选择、路线搜索、资源转移或攻击。串行和worker使用同一需求公式，巨大跨度先饱和再乘算，恢复沿同一余数；不建立另一套需求/运动规则。

普通`WorldContinuityRuntime._bind_navigation()`配置本接口。默认到期集合少于64人直接执行；较大集合按32人一个chunk、最多4个worker处理。无关身体不因跨格进入批次；`workers=0`用相同批数据串行计算，供对照。

采用时先完成相关身体的旧输入需求，再按稳定人物ID投影与通知。原执行器继续复核路径；路段已修复、取消或替换时不采用旧运动候选。`body_cell_crossed`/`body_space_changed`沿实际身体发出，行动、预约与取放效果仍归原owner。

身体显式同步、动作/控制/几何依赖失效、重建和成功restore撤销准备结果；失败restore不改变活世界及有效候选。原anchor与时刻也须匹配，同ID的新身体不能继承旧结果。

## 跨帧、存读与呈现

`RegionalSimulation`在边界开始前受理手动接管并执行一次手动移动，然后由原`SimSettlementKernel`的`native_interval/native_actors`步骤准备各地区批次。全部提交后检查完成；未完成返回宿主，原kernel保留游标，后续沿同一边界接续，手动位移不重放。

`has_pending_boundary()`读取同一个kernel的pending状态，涵盖native准备及后续阶段；`pending_boundary_ms()`读取其`at_ms`，不要求内部世界时间已经到达目标。地区提交后进入后续领域步骤，最终才发布`boundary_settled`及公共时间。等待期间外部命令和半步存档被拒绝，呈现保持最近完整状态；原owner的内部合法提交仍能完成。

存档只保存原身体、动作及共同时间。Packed输入/结果、线程handle、游标和计时不入档，不新增格式/迁移链。完整会话候选验证后替换世界、回收旧任务并重绑owner；坏候选不部分改活世界。

## 诊断与设备接缝

`actor_execution_work`有界记录准备/分配、提交、worker累计及时间跨度、排队、完成至收集延迟、原状态发布、采用/丢弃数和线程ID。输入提供者采样仍在主线程，发布包含原空间通知；worker数学耗时不等于整段身体推进成本。

普通诊断和人口压力报告包含各地区数据；`tools/stress_demo.py --actor-workers 0/4`对照相同路径。逻辑流速、帧P95/P99及真实渲染另行测量，线程ID/采用数只能证明接入。

GPU后续沿“紧凑输入、时刻/代次/依赖、候选输出、原owner采用”接入环境计算。当前需求采用64位整数，GPU布局与精度须按环境算法确定，不能改成浮点就假定同未来。本包没有新增GPU dispatch，旧独立GPU服务仍不算Main加速。

当前仍有主线程输入采样、地区/动作决定、路线搜索、领域同步及发布；准备也不是可抢占回调。本接口不证明300人1×/60FPS或所有规则已多核，证据见[BASELINE](../status/baseline.md)。

旧`test_actor_advance`已随全量套件退役，原验证范围保留在QA。当前`tests/smoke.gd`仅短查串行/worker数值一致及取消标记；完整世界采用、存读和长期稳定不由这个短检查证明。

官方依据：[WorkerThreadPool](https://docs.godotengine.org/en/4.7/classes/class_workerthreadpool.html)、[线程安全](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)。无新增依赖或业务autoload。
