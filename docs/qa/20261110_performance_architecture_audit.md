# 人口负载与运行架构调查

2026-11-10。受检生产代码为`839ff88f1b7fee240d0c798f533314a3ae446430`，最终游戏/测试代码为其祖先`c60a2beb2135d68990269f64e68cf3808396da3d`。本轮按用户授权将前者快进合入并推送main；同SHA的[CI42776609463](https://github.com/fewnfds/reol/actions/runs/42776609463)已核completed/success。本轮只做调查、临时实验和文档，不交付运行算法改动。

## 结论与可信范围

**需要改造执行结构。** 原状态所有权、共同时间、存读登记和领域划分有保留价值；局部精确边界驱动整条世界链、状态读取隐式推进、重复公共投影，使这些合理领域组合后的执行成本过高。已有`SimParticipationIndex`，问题是整条调用链尚未按实际工作收敛，不能再新建一套同名框架。

证据支持CPU侧同步工作存在明显瓶颈，尚不支持“Godot/GDScript已到极限”或“必须换ECS”。寻路是真热点，但不是全部；环境文件多也不等于环境占了大多数时间。允许破坏旧功能应当用于简化执行合同、退役重复入口，而非先拆掉全部领域。

硬件：i5-13600KF、约32GB整机RAM；Godot 4.7.2 stable Windows开发可执行文件。当前固定时间实验为headless，同步脚本段内没有实际绘制帧/物理帧；计时为`Time.get_ticks_usec()`差值，包含CPU工作、诊断开销及OS调度，**不是发布版帧时、GPU计时或16GB/RTX3060整机认证**。上轮原生100/300人约0.963/0.408×及画面证据单列于[压力QA](20261110_presentation_crowd.md)，不同实验不混作前后优化。

## 固定游戏时间测量

沿真实`crowd_scene.gd`和原行动提交：两地各6/50/150人，非玩家循环`rest → inspect → check_store → check_well`，进入work后取消并提交下一程；200次50ms公共推进，预算未完成则用原时钟继续，直到同样10000ms。初始化、第一次派单和最终快照写盘不在工作段计时内；200次查状态/改道的负载驱动成本包含在内。此次移除了旧对照脚本中5秒检查点写盘，不能直接比较旧6188/4674ms。

| 总人数 | 同步工作段，无插桩 | 世界完整边界数 | 改道次数 |
|---|---:|---:|---:|
| 12 | 3307.344ms | 703 | 43 |
| 100 | 9893.697ms | 2327 | 396 |
| 300 | 24979.082ms | 4231 | 921 |

每个完整世界边界都执行43个步骤，100/300人分别为**100061/181933次领域步骤调用**。这不是43个领域都做了同样多的有效工作，也不能仅凭调用数认定复杂度已呈平方增长；它证明局部事件目前确实放大全局调度。300人相对100人总耗时约2.52倍，不能把本组数据描述成实测O(N²)。

### 分项插桩

临时包装原方法、原kernel步骤，记录调用数、含子调用耗时及扣除已包装子调用的耗时；保留原回调、阶段、规则和预算。插桩总时间100/300人为12665.646/30038.007ms，相对各自无插桩样本增加约28.0%/20.3%，所以分项只用于定位，不作为发布版预算。下表**含子调用，不能相加**。

| 原路径 | 100人调用/毫秒 | 300人调用/毫秒 | 说明 |
|---|---:|---:|---|
| `SimGridNavigation.find_path` | 396 / 1698.375 | 921 / 5516.262 | 约占插桩总时间13.4%/18.4%；包括原生AStar2D与GDScript通行查询 |
| `VillageSimulation.next_boundary_ms` | 9020 / 963.518 | 17124 / 2531.990 | 已有截止堆，仍有失效重算与调用放大 |
| `VillageSimulation.actor_state` | 112197 / 1451.751 | 297281 / 3877.401 | 读取可能积分需求和投影原身体 |
| `VillageSimulation.materialize_actors` | 123139 / 1230.948 | 362239 / 3583.914 | 多数有快速返回；不能等同于每次全体重算 |
| `SimActionExecutor.project` | 29947 / 1080.010 | 86430 / 3005.655 | 到期与读取都可进入；内部仍有空间变化通知 |
| `previous:environment_fields` | 2327 / 1244.269 | 4231 / 1407.901 | 本样本约9.8%/4.7%，不能由文件数量推断它是唯一主因 |
| `WorldContinuityRuntime.actor_view_layout` | 597 / 1484.830 | 597 / 4306.746 | 只有200次公共步，布局却构建597次，读取原身体也在此发生 |
| `VillageRuntime._sync_actor_views` | 200 / 898.632 | 200 / 2587.390 | 身体可见性、pose、衣着与需求投影 |
| `WorldContinuityRuntime._refresh_views` | 397 / 1505.963 | 397 / 4361.031 | 远区全体候选、可见视图与重复布局 |

43个步骤的含子调用时间合计约2809.609/4206.521ms；它们在本样本里不是互相嵌套的步骤，但会包含上表其他方法。即使把整段寻路费用全部消除，300人插桩样本理论上也只约1.23倍提速；这是该样本的成本上界估算，不是候选算法实测。

### 临时剥离呈现的对照

再次取无插桩基线，然后临时将`_sync_actor_views`、`_refresh_views`、`_capture_committed_canvases`设为空操作。其余世界、规则、200次步进和改道保持不变，实际画面功能当然缺失。

| 总人数 | 本次基线 | 三类投影关闭 | 工作段减少 |
|---|---:|---:|---:|
| 100 | 10156.369ms | 9063.437ms | 10.76% |
| 300 | 24899.823ms | 23176.136ms | 6.92% |

这不是可交付优化，也不测GPU。它说明去掉这三类画面CPU投影仍不足以解决模拟吞吐；不能把投影方法的含子调用耗时直接当成可省费用。部分原身体补算会转移到负载驱动器等后续读取，正是更新/查询耦合的代价。两次无插桩100/300人基线分别相差约2.7%/0.3%，不是正式统计置信区间。

各人数的原版、插桩版、重复基线和投影关闭版都无world_errors，边界数、改道数及最终**整个world/clock/motion快照字节hash一致**：

- 100人：`3ea1ceef5ae2ce3a6df6d311e3343763b8d5ae8a22fe50a5d68ec8a5483d1fd9`
- 300人：`f2dfde1a6df35f946b5391a3ad6d8b4b4c2e84113fbcfdb48f10f3548bc2d8bc`

这只证明该固定负载终点，未检验每个中间时刻、长期饥饿/天气、多人争用或独立停开。临时插桩与剥离脚本均在忽略的`logs/`；执行器finally核对后逐字节恢复生产文件。原始结果为`perf-arch-results.json`、`perf-arch-view-results.json`及`perf-arch-*.log`，驱动与生成器为`perf_arch_driver.gd`、`perf_arch_audit.py`、`perf_arch_view_probe.py`。未新增永久回归组。

## 架构问题与改造边界

| 领域/主要owner | 已确认结构与风险 | 应改什么 |
|---|---|---|
| 共同运行：`RegionalSimulation`、`SimSettlementKernel` | 最小人物跨格/域边界进入完整43步，外层和内层重复求界；空工作也穿过适配与通知 | 保留原阶段顺序与续算，按到期/变脏及依赖选择实际执行；局部事件只唤醒相关消费者。固定公共步不是每局部事件全世界重算的理由 |
| 原身体/行动：`VillageSimulation`、`SimActionExecutor` | 到期投影已稀疏，但边界后settle和自主筛选仍遍历全体；getter可补算并发跨格signal | 使用原参与索引的到期动作/重试集合；把推进/写入屏障显式放在owner执行入口，读取只求值或返回已提交投影。迁完调用者再退役隐式补算/重入保护，不能先删屏障 |
| 空间/导航：`SimGridNavigation`、`SimMotionClearance` | 已用Godot原生AStar2D；每条候选边回调实时几何，许多人共享少量目标却重复搜索 | 静态几何按移动能力/净空与局部revision复用；动态阻碍另做局部复核。先比较原生AStarGrid2D/复用几何；同目标密集人群才比较共享flow field，不把所有不同目的地强塞一个场 |
| 呈现：`WorldContinuityRuntime`、`VillageRuntime` | 公共步重复构建全体布局，远区遍历后才判断可见；隐藏视图销毁/重建 | 同一公布时刻复用布局，局部可见候选与改变集合驱动视图；必要时池化。批绘前先量实际draw calls、CPU/GPU帧时和遮挡需求 |
| 环境：`SimWorldEnvironmentFields`及原来源/响应owner | 已有packed状态、到期索引、分片与原子提交；局部变化仍可能牵动较大准备工作 | 按真实改变通道/空间块降低传播范围，并测最慢原子工作。现有独立拆分不因“文件多”合成大类；不为普通走路建整区快照/事务 |

推荐形态是**现有固定公共时间窗口＋领域多频率/到期执行＋局部有序事件**，继续使用同一共同整数毫秒和原kernel。一个人物跨格可以需要人物、局部空间、携物热源和感知处理，不应该无条件唤醒炼器、衣着决策和所有聚落。窗口可以批处理事件，不要求把精确事件全部量化到窗口终点；先用此方式保留已有结果。

若随后为了简化合同选择动作量化、慢系统固定采样或环境近似，必须明列新精度/顺序与误差，再以新规则验收。确定性只要求同输入同规则得同结果，不要求无限精度。宿主卡顿不能改变已采纳事件的排序，也不能清空时间积压。渲染继续插值，和规则更新频率分开。

用户允许大改，意味着可以替换隐式getter、旧轮询和过宽同步入口；无须永久兼容这些内部实现。身体、原物、库存、账本和时间仍各有一个owner，存读沿原registry/codec；运行数据改成类型或packed列不必自动重写存档管线。只有格式真变更才按兼容政策处理，旧fixture不改写。

## 成熟项目与Godot方案

资料于本轮直接阅读官方开发日志、上游源码/README及AssetLib；没有把公开视频画面当成内部代码证据，没有安装候选插件或复制外来源码。

- [Factorio FFF421](https://www.factorio.com/blog/post/fff-421)：空闲roboport休眠、重叠雷达区域共享登记、已知运动意图减少机器人逐tick更新。借鉴活动集合、覆盖登记和预计到达；文中收益只属于Factorio，不能套为Reol提速承诺。
- [Factorio FFF364](https://www.factorio.com/blog/post/fff-364)：并行输送带要隔离关联范围，并保留有序唤醒。先减少工作，再决定线程；不能让worker完成先后决定药物/攻击结算。
- [RimWorld Multiplayer的AsyncTimeComp](https://github.com/rwmt/Multiplayer/blob/master/Source/Client/AsyncTime/AsyncTimeComp.cs)：可核查Normal/Rare/Long三个TickList及分阶段地图更新。它是社区mod，展示公开接口的使用，不是RimWorld官方内部源码审计；借鉴分频登记，不照搬其联机/异步地图时钟。
- [Mindustry Pathfinder](https://github.com/Anuken/Mindustry/blob/3193fd81681476f3fa08bbcf3d7efb89e67229bd/core/src/mindustry/ai/Pathfinder.java)：分离通行数据、按队伍/代价/目标类型缓存flow field、合并dirty刷新并预算扩展。适合大量共同目标；其线程和刷新延迟不是Reol既有合同。GPL项目只研究思路，不复制源码。

| 候选 | 核对到的版本/许可/示例 | 本项目取舍 |
|---|---|---|
| Godot原生AStar2D / AStarGrid2D | 4.7；现代码已经用AStar2D。[官方AStarGrid2D](https://docs.godotengine.org/en/4.7/classes/class_astargrid2d.html) | 优先对照几何复用与回调费用，不再购买一层A*包装。不同worker需独立搜索实例，不能共享当前可变图 |
| Godot RenderingServer / MultiMesh | 4.7官方[Servers](https://docs.godotengine.org/en/4.7/tutorials/performance/using_servers.html)、[MultiMesh](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html)及fish示例；引擎MIT | 优先复用。密集同材质对象可分区批绘；MultiMesh没有逐实例裁剪，人物层次/遮挡/雾不能直接丢弃，也不负责需求与事件结算 |
| [GECS](https://godotengine.org/asset-library/asset/3481) | AssetLib 7.0.1标4.4/CC0；上游`release-v8.0.0`要求4.6+，含stress/MultiMesh示例。[LICENSE](https://github.com/csprance/gecs/blob/release-v8.0.0/LICENSE)为CC0-1.0，README末尾写MIT，存在说明不一致 | 参考query成员缓存/系统分组；本轮不引入。它使用Node/Resource，不等同于原生连续内存ECS；迁入全部owner不会自动消除全局边界 |
| [LimboAI](https://godotengine.org/asset-library/asset/4852) | 1.8.1，MIT；上游1.8.x GDExtension标4.6+，module标4.7；`demo/scenes/showcase.tscn` | 后续认识/AI编排与调试可独立评估；不是模拟结算或存读性能插件。未在本项目4.7.2实测 |
| [Godex](https://github.com/GodotECS/godex) | MIT引擎module；README只声明测试过特定Godot master提交，仍在开发 | 本轮不采用；需要定制引擎构建，未见本项目4.7.2兼容验收，代价远大于本次执行层收敛 |
| [flow_field_pathfinder](https://github.com/ChrisTutorials/flow_field_pathfinder) | README明确DEPRECATED/reference only，无预编译Godot扩展；自定义Chris' Tutorials Plugin Asset License v1 | 排除直接依赖。能看到仓库/demo并不代表可维护或许可适合；需要flow field时先比较算法收益 |

Godot负责原生搜索、几何/碰撞服务、渲染、线程设施与诊断；游戏继续负责规则时间、事件仲裁、跨域影响和恢复。Godot `_process`/物理帧以及上述插件不会自动处理离场世界、存档中的在途行动和药物/攻击的业务顺序。

## 计划与本轮停点

将上述改造收进[唯一基础计划](../plans/foundation-priorities.md)的共同运行、空间/行动、呈现与联合规模，旧[效率审计](../plans/runtime-efficiency/README.md)仅作历史结构参考。近期先改变调度和读取合同，再按实测整合导航与呈现；不另开ECS迁移、第二事件引擎或逐函数优化清单。

本轮9次实验结束，生产文件已恢复，没有运行中的测试/引擎/审查handle。文档结构检查335份当前文档/522份脚本、0错误，差异空白检查通过；纯文档包未再启动引擎/完整回归/模型审查。后续验收应补发布版原生CPU/GPU分项、100/300人长时持续移动及拓扑变化，性能与同未来/中断/存读分别证明。
