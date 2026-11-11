# 批计算与原状态提交

本合同属于共同运行与数据底座。交付顺序只在[主计划](../plans/foundation-priorities.md)，总体因果见[共同结算](settlement-contract.md)；本页说明当前CPU接入，不代表整个多核方案或规模性能通过。

## 任务、数据与所有权

[SimBatchExecution](../../scripts/sim/execution/batch_execution.gd)持有一次可回收任务，使用Godot `WorkerThreadPool.add_group_task()`。共享输入在提交前固定，每个chunk拥有私有输出和计时；worker只调整自身输出，不调整共享容器大小、不访问活SceneTree、不调用世界提供者、不写身体或库存。它不另持世界时钟、实体库或业务回执。

任务Callable只保留scratch `WorkGroup`，不反向保留handle、世界或场景。原owner可用`finish()`保留pending游标，或在后台协调线程等待必须的依赖；主线程只轮询一次世界邮箱，不等待批计算。完成后收集Godot任务资源。`cancel()`撤销采用权，已运行的有界chunk可以结束；owner保留退休handle并在随后推进时收集。退出/世界替换负责最终回收，清理时可以等待。

线程完成顺序不决定游戏顺序。原owner检查时刻、代次、依赖及原对象，再按领域顺序提交；资源争用仍沿原预约/账本。计算结束不等于动作生效。

`workers`是本批使用线程池的并发上限，不是游戏总线程数。`0`沿相同算法串行；`-1`根据本机逻辑处理器和独立chunk数选择，较大机器为主线程/协调者留两个执行槽；显式1–64用于对照，实际不超过逻辑处理器、chunk数及Godot线程池容量。单chunk或只剩一个槽时直接串行。不再硬限8；自动模式按硬件/任务量适配，不冒充在线学习最优并发。生产默认档及实测选型只查BASELINE。

## 原身体连续推进

[VillageSimulation](../../scripts/sim/village_simulation.gd)选择当前到期人物，为[SimActorAdvance](../../scripts/sim/actor_advance.gd)准备需求固定点值/余数、有效速率、体力/恢复条件、旧锚点、目标时刻及已受理路段。稳定ID、动作ID和采用依据留在原owner线程；worker只读`PackedInt64Array`及`PackedVector2Array`。

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

`SimGridNavigation.Search.find_path`可在私有AStar上下文上运行同一算法。同步便利入口仍使用协调者的缓存；worker不得调用该全局缓存，也不得共享一个正在搜索的AStar。首批只验证了私有上下文批查询，尚未把普通行动的即时路线请求改为异步。

[SimBodyReadView](../../scripts/sim/body_read_view.gd)在原规则边界由owner同步所需地区并捕获身体ID、位置、高度列；worker不触发身体getter。它保留原地区/人物遍历顺序，当前每批捕获一次，该战斗读取表不承担显示发布；显示使用下述独立纯数据视图。

[SimSpatialQueries](../../scripts/sim/execution/spatial_queries.gd)按64个身体分块，对多个线段求接触候选；达到4096个身体×线段候选对才尝试最多4个worker，小批用同算法串行。任务内一次解析列引用，避免每对候选重复访问共享脚本对象。候选按固定chunk顺序收敛，等距仍由原身体顺序决定。

真实消费者是`SimConflicts._advance_projectiles`：同边界捕获一次身体输入、批量查候选，再沿原投射物顺序核遮挡、收集全部接触、最后沿原规则提交伤害。此首批接入仍在原交锋回调内等待完成，没有跨帧交锋游标或新的取消时机；大批的等待也计入回调成本。不是每个领域独建线程或第二个战斗世界。

## 身体发布与环境计算

`SimBodyPublication`复用`VillageSimulation.body_read_roster()`成员表，64人一块准备位置、姿态、衣着及原身份；结果不保留原身体/动作引用，少量玩家/选中需求由原owner补齐。输入只在owner等待此批时借出，不允许并发写；最终Node/贴图更新在主线程。

`SimFieldCompute`使用已有compact场job和相同整数max方程/材质穿行，按16×16格给任务私有输出，串行与worker共用公式；原场owner验证输入版本与候选证明后采用。GPU路径原样保留，CPU模式与无渲染设备时使用任务池。

`SimFieldResponseInput`在候选field完成后，为各tile准备温度/五行目标列；私有compiler只共享不可变定义、拥有独立memo。原temperature/phase owner保持历史、范围、容量和锚点复核，提交仍同步有序。小量/禁用worker可沿相同输入类分预算运行；取消先收集正在读取的任务再丢候选，不在任务尚读时修改原响应数据。

## 协调线程、存读与呈现

`SimWorldRunner`持有原世界的一次独占执行权，常驻线程处理单个时间请求；CPU批和GPU候选仍使用原kernel游标。原手动移动每区间只积分一次，不按渲染帧重复。需要依赖时后台等待实际完成，主线程继续绘图。

`ReolSimulationHost`在运行期间暂缓旧世界读取回调；`ReolSimulationSignalBridge`只记下领域向Node的通知，内部领域信号继续同步。完整边界返回后恢复原连接并递送通知、处理缓冲输入及旧UI/画布读取，然后才能发下一请求。绘图函数只读提前捕获的显示值，人物/镜头插值可与模拟并行；其他画布尚非完全异步快照，交接尾部是测量项。

存档只保存原身体、动作及共同时间。输入/结果、线程handle、游标和计时不入档；保存时等待同一完整边界，加载/退出先回收旧协调者和批任务。坏候选不替换活世界，开发期不新增历史兼容链。

## 诊断与验证范围

普通压力报告含`actor_execution_capture`、`body_publication_capture`、`simulation_host`、`publication_work_including_setup`及环境CPU/GPU/响应计数。worker微秒是经过时间，Windows `--profile-cpu`侧录才是线程真实CPU；按capture起止时间排除装配。

`--simulation-thread off`、`--actor-workers 0/4/8`和`--release-binary`用于同构建对照。`--input-probe`测无副作用宿主请求等到完整边界的延迟，不冒充玩家输入到像素的端到端延迟。

短`spatial`检查包括同输入场/响应列串行与worker一致、身体发布不保留原对象、Node信号在交接后递送及恢复连接；不证明所有玩法或长期性能。真实规模、暂时方案和未测范围只记BASELINE。官方API依据见[执行设计](../specs/world-engine/execution.md)。
