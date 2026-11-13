# 大型模拟：参考来源与选型理由

核查日期：2026-11-12至13。本页只保留公开来源和仍有价值的选型理由。当前实现见[架构](../../docs/engineering/architecture.md)，周期/近似见[运行与精度](../../docs/engineering/simulation-pacing.md)，测量见[BASELINE](../../docs/status/baseline.md)。

旧框架的逐步借还活世界、全域刷新和同步GPU回读链已经退出运行。完整排错、咨询次数、阶段顺序、失败原型与当时结论查[整理前研究](https://github.com/fewnfds/reol/blob/02958cc/design/research/large_simulation_optimization.md)；这些过程不再作为当前任务保存。

## 成熟项目与引擎

来源核查于2026-11-12至13；公开资料说明可借鉴的思路，不保证Reol的性能。原始研究过程由Git追溯。

| 一手来源 | 可证实的设计与边界 | 借鉴范围 |
|---|---|---|
| Factorio [FFF70](https://www.factorio.com/blog/post/fff-70)、[FFF150](https://www.factorio.com/blog/post/fff-150) | 更新、准备、绘制有不同责任；可以减少绘制维持模拟更新，准备仍有同步条件；更新本身过载仍有UPS上限 | 消除每步等画面收取，不承诺任意负载始终维持4倍 |
| Factorio [FFF421](https://www.factorio.com/blog/post/fff-421) | 静态/休眠对象避免每tick无用更新；具体改动的收益依赖实际对象行为 | 静态地形画布和静态环境不每步重建；不照搬其收益数字 |
| [OpenRA Game.cs](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Game/Game.cs)、[World.cs](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Game/World.cs) | LogicTick、RenderTick和世界tick职责清楚；普通游玩路径仍包含logic后必须render的约束 | 借鉴责任划分，不把它说成完全没有显示/模拟耦合的现成模板 |
| Mindustry [AsyncCore](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/async/AsyncCore.java)、[PhysicsProcess](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/async/PhysicsProcess.java)、[Logic](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/core/Logic.java) | begin/process/end有join；物理任务按不相互作用的碰撞层并行 | 按独立页/结果并行，避免每个领域一个自由推进线程 |
| [OpenTTD 主循环](https://github.com/OpenTTD/OpenTTD/blob/master/src/openttd.cpp) | 车辆、地块、脚本等在游戏循环内各有职责/周期；不是所有东西每画面帧调用 | 保留共同时间但按领域频率唤醒，普通移动不强迫慢环境结算 |
| [OpenRCT2 Context](https://github.com/OpenRCT2/OpenRCT2/blob/develop/src/openrct2/Context.cpp) | 游戏更新累加器可在一次绘制前执行多次更新，插值与权威位置分开 | 倍率完成更多相同步；画面只使用已提交位置，不伪造未来 |
| Veloren [state.rs](https://github.com/veloren/veloren/blob/master/common/state/src/state.rs)、[server](https://github.com/veloren/veloren/blob/master/server/src/lib.rs) | Dispatcher调度并行系统，维护实体结构与本地事件采用有明确阶段 | 并行独占身体页，跨单位/资源效果由owner采用；不照抄其Rust/ECS开销 |
| [Flecs Systems](https://github.com/SanderMertens/flecs/blob/master/docs/Systems.md) | staged结构变化、worker切片与immediate单线程系统有不同限制 | 不把ECS当万能提速器，不为低频业务强制表迁移/批接口 |
| [RimWorld官方公告](https://store.steampowered.com/news/app/294100)、[Ludeon](https://ludeon.com/blog/) | 公开公告可用于核对已披露的优化范围，不能据此得知完整内部调度 | 成熟项目也会针对瓶颈重构；不能据公告推断其所有Pawn逻辑、GPU模型或照搬内部class |
| Godot [线程安全](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)、[WorkerThreadPool](https://docs.godotengine.org/en/4.7/classes/class_workerthreadpool.html) | 活SceneTree不能任意多线程访问；任务量不足时调度可能负收益 | 不碰场景的独占页批；引擎管理池，不自造每域线程池 |
| Godot [PackedVector2Array](https://docs.godotengine.org/en/4.7/classes/class_packedvector2array.html)、[C++ core types](https://docs.godotengine.org/en/4.7/tutorials/scripting/cpp/core_types.html)、[cowdata.h](https://github.com/godotengine/godot/blob/4.7/core/templates/cowdata.h) | GDScript Packed数组是引用值，需要duplicate/新目标拷贝才能独立；C++容器的CoW不能证明脚本共享写安全 | 生产者新建脱离Frame，发布后不写；保留旧帧不导致槽位覆盖 |

## 官方性能指南逐篇核查

[Godot性能目录](https://docs.godotengine.org/en/4.7/tutorials/performance/index.html)用于定位方法；下表保留逐篇适用性，具体实现与参数由工程页维护。

| 官方子篇 | 当前结论 |
|---|---|
| [General optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/general_optimization.html) | 测量端到端、区分装配与稳态；只保留真实收益，不用短smoke代替容量 |
| [Using servers](https://docs.godotengine.org/en/4.7/tutorials/performance/using_servers.html) | 逻辑为纯数据；绘制使用Godot原生MultiMesh，不重写通用渲染器 |
| [CPU optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html) | 连续热列、局部缓存、避免大量小对象/跨格广播；低频逻辑仍可简单直接写 |
| [GPU optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/gpu_optimization.html) | GPU绘制与compute回读是不同成本。当前删除小批CPU必等的GPU逻辑场，保留显示GPU数学 |
| [Using MultiMesh](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html) | 同类人物原生批绘；实例数据适合批绘；跨人物/地物排序和多层外观仍需具体设计 |
| [Using multiple threads](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multiple_threads.html) | 一个自主模拟线程，独立页批处理；命令/通知与只读快照交换，不借还活世界 |
| [Thread-safe APIs](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html) | 共享容器不并发变长；同一个Packed引用不并发写；场景/资源操作留主线程 |
| [Optimizing 3D performance](https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html) | 当前为2D，不引入GI/3D遮挡/网格LOD；只借鉴分块裁剪与共享资源思想 |
| [Vertex animation目录](https://docs.godotengine.org/en/4.7/tutorials/performance/vertex_animation/index.html) | 视觉变形/动画可以留GPU；不能把显示控制点当真实身体事实 |
| [Controlling thousands of fish](https://docs.godotengine.org/en/4.7/tutorials/performance/vertex_animation/controlling_thousands_of_fish.html) | 群体控制适合装饰实例；NPC仍保留各自实际路线、资源和后果 |
| [Animation of thousands of objects](https://docs.godotengine.org/en/4.7/tutorials/performance/vertex_animation/animating_thousands_of_fish.html) | 采用实例数据+GPU动画思想；脚点和朝向仍来自真实单位数据 |
| [Pipeline compilations](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html) | 装配/首次图集shader预热与稳态分开，不用预热掩盖持续模拟成本 |
| [Background loading](https://docs.godotengine.org/en/4.7/tutorials/io/background_loading.html) | 当前有限切片未恢复分块加载；将来异步资源准备不应获取活世界的全局锁 |

Background loading是相关补充，不属于原performance目录。MultiMesh/鱼群篇标记旧版的示例仅借用思想，实际API按4.7核对。官方目录随版本变化；本文针对实际4.7，不假装其给出了本游戏通用插件或无限人口承诺。

## 全单位感知与战斗视野咨询

OpenRA的[AutoTarget](https://github.com/OpenRA/OpenRA/blob/playtest-20261026/OpenRA.Mods.Common/Traits/AutoTarget.cs)、[AttackFollow](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Traits/Attack/AttackFollow.cs)与[FrozenUnderFog](https://github.com/OpenRA/OpenRA/blob/playtest-20261026/OpenRA.Mods.Common/Traits/Modifiers/FrozenUnderFog.cs)分别提供局部索敌、最后可见目标和静态记忆的公开参考。[Mindustry FogControl](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/game/FogControl.java)展示当前/探索位集，但其AI特殊豁免不适合直接搬用。

共同感知查询与玩家显示图承担不同规模的工作；给每个NPC视距不必为每人生成整张地图。0 A.D.的[LOS纹理](https://github.com/0ad/0ad/blob/master/source/graphics/LOSTexture.cpp)可参考逻辑和显示分离。Reol更密CPU采样/四邻缓存曾增加成本而撤回，不据此禁止其他有证据的算法；实际精度归工程页。

## 临时像素美术的清单与源码核查

采用现成许可明确的物品、生成后规整的人物/自然物与程序规则图块。原因是统一临时观感，同时保留离线重建能力；完整清单、许可和素材入口只归[assets](../../assets/README.md)。

[Godot TileSets](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html)允许图块区域、原点和terrain邻接独立表达；图集切片不等于世界占地。[Mindustry Tile](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/world/Tile.java)提供自然floor、overlay、block分层的公开例子。贴图裁边与锚点需要看真实源图，扩大图集槽位不能恢复已丢失的树冠。

## 任意角度移动：方案核查与实施

- [Red Blob格网优化](https://www.redblobgames.com/pathfinding/grids/algorithms.html)、[Theta*原论文](https://idm-lab.org/bib/abstracts/Koen10r.html)、[GridStringPulling](https://arongranberg.com/astar/documentation/stable/gridstringpulling.html)：格图搜索和任意角路径可以分开，事后拉直不保证全局最短。
- [0 A.D.寻路接口](https://github.com/0ad/0ad/blob/master/source/simulation2/components/ICmpPathfinder.h)与[历史设计说明](https://www.indiedb.com/games/0-ad/news/the-pathfinding-saga-continues)：长/短距离路径、身体尺寸、请求身份与运动检查分别负责。
- Godot [AStarGrid2D](https://docs.godotengine.org/en/4.7/classes/class_astargrid2d.html)、[NavigationServer2D](https://docs.godotengine.org/en/4.7/classes/class_navigationserver2d.html)与[导航优化](https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_optimizing_performance.html)：前者单图不能并发搜索，后者支持并行查询但有地图同步边界。

生产选择lane私有AStarGrid通路加净空拉直，因为它契合动态方格建筑和自主模拟时钟；NavServer纯数组原型也通过过窄道反例，不能把未采用解释为原生方案不可用。双相位体型图避免大身体整格膨胀误封两格宽通道。带时间的折线避免显示/弹道用端点弦线切角，准备额度分散请求但不是单次搜索的硬耗时上限。后续若品质或端到端成本不足，可以重选表示。

顾问用于发散和反例，未经执行的百分比、闭源内部实现及“零成本”承诺不作为事实。实际调用方式只在本机说明维护，已结束的请求记录不持续追加到项目计划或接口页。
