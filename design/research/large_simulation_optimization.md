# 大型模拟：参考来源与选型理由

核查日期：2026-11-12至15。本页只保留来源、局部实验和选型理由。当前实现见[架构](../../docs/engineering/architecture.md)，周期/近似见[运行与精度](../../docs/engineering/simulation-pacing.md)，成品测量见[BASELINE](../../docs/status/baseline.md)，当前工作查[主计划](../../docs/plans/foundation-priorities.md)。

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

## RTS性能视频字幕核查

2026-11-15用户提供03:37～05:28的字幕，没有视频链接、源码、硬件或原始报告。字幕叙述万级至十万级单位的高FPS、20Hz逻辑、连续数组/线程池/MultiMesh/流场、GPU动画与落点表现，以及每格最多4个对象会漏近战。这里将其作为技术线索，数量/FPS未独立复现，不作为Reol的目标或容量证据。

| 字幕做法 | Reol源码现状 | 适用判断 |
|---|---|---|
| 大量单位不用逐个Node，热数据连续存储、线程分块 | Units为256行Packed页，World/Lane独占批，WorkerThreadPool已有；动作/状态为领域实例，未把整个世界压成一张表 | 继续在真实热路径使用紧凑列；低频复杂语义不必为了数组化而重写。Resource保留内容制作作用 |
| MultiMesh、GPU插值、动画相位错开 | Population批量缓冲/Shader轨迹与图集动画已有，按身份错开节拍；主线程消费已提交Pose | 已具备主要原则。后续量CPU缓冲准备/跨地物排序/上传/裁剪，不重做一遍基础批绘 |
| 均匀网格 | CombatScan分阵营桶，heads/links遍历全部在桶单位，没有每格4人上限 | 可以减少重复构建、复用有效候选；拥挤时不能静默截断伤害资格。广相位筛选与窄相位扫掠分开 |
| 20Hz逻辑＋高帧率画面 | 当前60Hz共同心跳、到期细分，慢域各有频率；显示独立插值 | 渲染顺滑不增加输入/命中采样。20Hz是50ms一步，60Hz约16.7ms；不为视频FPS全局改回20Hz。未来只按领域及实际接触依赖减少工作 |
| GPU计算飞剑整条抛物线，模拟只记落地时间 | 区域预警/到期已经可用轻量逻辑事件；箭/飞剑还有扫掠、受损、追踪、回收等事实 | 纯轨迹装饰/落点效果可参数化给GPU；具有沿途后果的对象仍需CPU逻辑状态。可先算逻辑接触再画装饰，不强制每个画面像素有模拟实体 |
| 平滑流场过桥 | 当前每lane AStarGrid2D、路径缓存、有限净空平滑/节流 | 流场适合很多单位共享目标/通行政策；不取代全部生活独立目的地。流向平滑、局部避让和拥挤通行是不同问题，流场本身不保证不重叠 |
| 用位运算替代除余以改善多线程 | 页大小256、部分索引常量为二的幂；另有连续坐标、负哨兵和不同除数 | 只在非负整型、二的幂且实测为热点时替换；例如负数向零取整的除法不能随意换算术右移。没有全库替换政策 |

官方[MultiMesh](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html)明确单个MultiMesh没有逐实例裁剪，可按区域分批；但Reol的2D人物/地物共享脚点排序，分批必须同时解决跨块/跨物遮挡。[WorkerThreadPool](https://docs.godotengine.org/en/4.7/classes/class_workerthreadpool.html)明确轻任务可能负收益；线程池存在不代表工作足够粗。[物理插值说明](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html)解释固定更新与渲染的分工和低tick影响；Reol使用自己的共同时间，不直接启用第二套物理时钟。多线程历史问题如[#65404](https://github.com/godotengine/godot/issues/65404)来自旧版/特定负载，不能直接证实4.7除法缺陷。

流场的适用性参考[Red Blob：Flow field pathfinding](https://www.redblobgames.com/blog/2024-04-27-flow-field-pathfinding/)、[塔防共同终点](https://www.redblobgames.com/pathfinding/tower-defense/index.html)和[jdxdev流场实践](https://www.jdxdev.com/blog/2020/05/03/flowfields/)；后者同时记录群体绕角仍可能挤成线，不能以流场名称替代实际窄口行为验证。均为算法参考，不搬用其帧率或语言后端结论。

### 整数运算的本机对照

Godot4.7.2 stable ed1daf0bf，i5-13600KF/20逻辑核；1,048,576个非负整数、16独立块，循环使用typed局部变量，无逐项共享写，末尾保存校验和；同一次运行1次预热、3次计时取中位。分线程时间含池派发/join，各组结果校验和均为2280652800。release为同逻辑单独导出的标准模板，未修改引擎。

| 操作 | 调试引擎串行 / 4worker | release串行 / 4worker |
|---|---|---|
| 整数除256＋余256 | 31.075 / 59.293ms | 17.228 / 4.737ms |
| 右移8＋按位与255 | 16.864 / 4.369ms | 13.887 / 4.054ms |

调试引擎复现了视频描述的退化，release中除余能并行加速。因此不能把“整数除法/取余不能多线程提速”当作通用引擎断言。位操作在这个标量循环较快，不代表全游戏会有相同比例收益；对象属性访问、共享引用、分配、任务大小与实际CPU均需分别考虑。本实验没有定位引擎内部根因，也没有比较不同Godot版本。

脚本及临时最小导出项目在`.local/performance-20261115/`；结果在`logs/integer-scalar-probe.json/.log`与`logs/integer-scalar-release-probe.json/.log`。首次尝试给项目release使用`--main-pack`被模板明确拒绝；改为导出独立最小程序后才取得release结果，不计失败命令为通过。所有探针留本机，不入正式游戏或根目录。

### 当前成本线索

临时CPU归因探针使用同一P4源码、headless调试引擎、串行身体、1世界秒预热＋5世界秒，不按墙钟限速；仅用于定位，不表示真实FPS或release容量。记录在`logs/framework-cost-probe.json/.log`。

24人持续按住裂星箭，300个主步产生455个细段、空间索引构建555次；150人、相同3敌近场加后台人物，300主步/693细段、构建793次。后一窗World.step累计约685ms，空间索引约150ms，原生搜索约0.57ms、路径几何约12.76ms；Effects.prepare约16.26ms，Reactions.prepare约8.09ms，发布平均约0.347ms/步。各计时有父子嵌套，不能相加成总成本；计时插桩本身也有开销。两窗峰值9个在飞弹，不能外推密集弹幕；角色/作业/随机进程不同，不把人数差算纯算法倍率。

这一负载更值得先查共同细分引起的全体准备/索引与发布成本，尚无用流场替换全部A*的证据。状态/因果链扫描目前占比小，不能因代码可优化就先引入复杂计数或永久调度器。24人真实release的当前证据归BASELINE，未证明大世界必须降精度。

另一次仅增加完整慢视图次数统计的相同CPU探针（`logs/framework-publication-probe.json/.log`）发现，300次发布中，24人默认/24人连发/150人连发分别有92/113/240次进入完整慢视图，确实超过单纯100ms周期，但不能称所有战斗帧都触发。`outcomes/receipts`目前都能强制完整视图，通知队列本身在分支外交付；未来应分别核对HUD/详情刷新与统计成本，不直接删除触发条件冒充无风险。

### 顾问复核与开发者取舍

本机两题咨询分别核查字幕方案和新增测量后的施工次序，原件在`.local/advisor/framework-optimization-20261115/{review,measured-review}/`。首题argon已完成，hydrogen因上游RECITATION结束且无有效正文，未自动重试；第二题附本机新证据，argon与hydrogen均已完成并核查。失败答复不充作意见，顾问原文不作为源码或运行事实。

首题偏向先精简Frame；附新测量的第二题两份答复均建议先补release归因，倾向优先减少索引/全员准备，延后Frame全面改造。采用“先量实际操作负载、再选最小改动”的施工顺序：审查全体被子段带动的工作量、按几何有效性复用索引，发布字段投影只在相关成本成立时推进。最终以相关release操作负载裁决，不把顾问倾向写成主要瓶颈已证实。附带纠正：

- `Objects.total()`读取现有汇总，不是全物品遍历；`counters()`会遍历身体列。统计触发次数也须实测，不能假定全60Hz。
- 单个子项占总时长的比值不等于可移除收益，父子计时不能相加；批次总挂钟减最长任务也不等于纯join开销。调度等待、起跑错位和负载不均需分开看。
- 重复调用之间可能已有运动或结算，不能把793次索引中的固定数量直接判为可删；顾问给出的“消除80%+”没有对照测量，不采作收益承诺。空表短路也须处理旧贡献清除，不能留下上一状态的移速修饰。
- `bucket(low/high)`可接收地图外的负查询边界，不能只因单位坐标非负就把浮点floor改成int右移；先保类型、负数和边缘语义。
- 当前60FPS短窗有限帧，帧间隔接近16.67ms不代表主线程用满，代码关闭VSync；CPU/GPU工作、限帧等待和发布独立看。顾问未看到完整图形报告时猜测VSync，不能沿用。
- 只改Frame投影不等于改存档；已交付来源快照、规则/过程状态继续随原owner保存。慢视图变化处理会影响可见反馈，不能称“零风险”。
- 不采用顾问给出的固定人数/状态数/FPS或毫秒门槛，也不把整段全状态hash相等升级成全游戏长期确定性要求。只对本次缓存/发布改动核相关结果与旧视图不可变。
- 不把DoT、区域或作业到期强行对齐另一网格来假装纯优化；这可能改变伤害、死亡/工作先后。未来确需近似时先明确允许的延后/遗漏。活动表只限制需要执行的宿主，受击查询仍覆盖可能被流弹/范围打到的非交战者。

具体三包范围与出口唯一维护在主计划；大世界近似、共享目标流场与活动区推进目前仍是条件候选，未实施。

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
