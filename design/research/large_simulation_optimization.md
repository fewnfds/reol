# 大型建造与模拟游戏的性能方法

> 研究资料：记录来源与适用限制，不授予引入依赖或改变规则的权限。

调研：2026-11-06，2026-11-11补充普通300人运行、外部建议、分频及多核执行。范围是运行链、环境场及世界数据；记录来源与适用边界，不改变[环境规则](../rules/environment.md)，也不构成新的任务队列。当前授权、有效测量与实施优先级分别看[接续](../../docs/status/handoff.md)、[BASELINE](../../docs/status/baseline.md)与[主计划](../../docs/plans/foundation-priorities.md)。

## 结论与选型

成熟项目的共同路线是：减少无效工作，组织连续数据，批量处理，再对独立任务并行。分块、休眠、缓存、线程、GPU不是互相替代的万能方案，分别解决不同成本。

持续活动、初建和存读是不同负载，需要分别定位成本。本页保留可复用的研究思路与来源；早期代码归因见历史快照，当前实现与测量只查工程接口及BASELINE。

Reol已有分块、局部失效、packed响应列、分段二进制及基础场GPU实现。大地图初建/存读仍可研究：

1. **基础场初建**：先拆开来源装配和场计算，统计逐通道访问量；对CPU评估局部空间上界/稀疏来源，对GPU评估接入已有基础场计算的完整成本。
2. **大档存读**：先区分编码、解析、校验、I/O和原世界候选恢复；对高重复段评估类型化列、数字字典和批量读写，而非再次宣称“改成二进制”。

这些是按负载选择的研究方向，不替代普通游戏的性能目标。当前没有充分证据把瓶颈归结为Godot引擎上限，也没有依据承诺优化后必然几秒加载。

## 多核执行（2026-11-11）

这里核对成熟项目的一手经验；实施结构只维护在[计算接入](../../docs/engineering/execution-batches.md)，阶段顺序只见主计划。来源本身不能证明Reol性能达标；旧代码归因在[历史快照](../../docs/archive/qa/20261111_compute_research_snapshots.md)，不用于定位当前实现。

关于worker数量，再核对[Godot线程池](https://docs.godotengine.org/en/4.7/classes/class_workerthreadpool.html)和[项目设置](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html)：线程池在启动时维护工作线程，每次group可以选择参与数量，默认`tasks_needed=-1`使用所有可用worker；不是每批重新创建线程。池上限为-1时，桌面平台按逻辑处理器数配置，小任务仍可能变慢。[Unity Job System](https://docs.unity.com/en-us/engine/6000.0/manual/scripting/programming-distribute-work-threads/job-system)采用任务与依赖的同类职责划分；不把其C#/原生性能或调度实现当作Godot保证。

因此固定4/8只是实验档，不是核心数的永久限制；Reol补充按硬件/批量选槽与高并发对照。FFF421既有独立读计算成功，也有线程CPU占用大升但整局不快的电网实验，支持实测端到端和准备/采用成本；它没有给出适用于Reol的最佳worker数。没有公开依据声称RimWorld按某个公式动态调整全部游戏线程。

| 一手资料 | 可采用的经验 / 适用边界 |
|---|---|
| [Ludeon：Odyssey与1.6公告](https://ludeon.com/blog/2025/06/announcing-odyssey-and-update-1-6/)，2025-06；[官方Steam公告](https://store.steampowered.com/news/app/294100/view/498322216088241321) | 官方明确把寻路改为批量多线程，并并行照明。采用“批量独立查询”的职责划分，不声称RimWorld全部模拟已经并行；公告没有提供其完整内部数据/调度实现。此次网页直取受403/正文展示限制，已通过Steam官方`ISteamNews/GetNewsForApp`读取同标题正文核实 |
| [Ludeon：Waylith与1.7公告](https://ludeon.com/blog/2026/10/announcing-the-waylith-engine-and-update-1-7/)，2026-10-12 | 截至本次调研公告将其作为unstable测试，声明专用引擎带来性能改善；经上述Steam官方接口核对。说明不能把多年前单核印象当最新状态；这份公告不能推出Reol应更换引擎、也不能将其宣称倍数换算为本项目收益 |
| [Factorio FFF421](https://www.factorio.com/blog/post/fff-421)，2024-07-26 | 只读带式计数/组合器计算能够并行，输出再采用；全局随机流需处理。电网并行因共享消费者与内存带宽失败，说明还要量输入布局、带宽和端到端成本；这不是继续回避多核的理由 |
| [Factorio FFF215](https://www.factorio.com/blog/post/fff-215)，2017-11-03 | 并行跨实体更新可能因共享缓存行互相干扰；线程和数据分块要一起设计。其当时全量更新实验不能当作2026所有模拟游戏的上限 |
| [Factorio FFF415](https://www.factorio.com/blog/post/fff-415)，2024-06-14 | 核心数改变曾影响地图生成结果；必须让任务分割与效果顺序、随机语义分开。只选有关的线程数/顺序反例，不由此恢复冗长回归 |
| [Epic MassEntity概述](https://dev.epicgames.com/documentation/en-us/unreal-engine/overview-of-mass-entity-in-unreal-engine) | 连续数据块、无状态批计算、结构变化延后合并；借鉴数据/过程分离，不引入Unreal或要求先搭完整ECS |
| [Godot 4.7线程池](https://docs.godotengine.org/en/4.7/classes/class_workerthreadpool.html)、[线程安全](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)、[线程组](https://docs.godotengine.org/en/4.7/classes/class_node.html#class-node-property-process-thread-group) | GDScript可用现成worker；活SceneTree不能任意并发访问，同一AStar对象也不能并发查询。用私有执行槽/共享只读输入；线程组不自动拆解RefCounted世界。小任务并行可能亏损，不等于主要负载不必并行 |

[Godot性能目录（中文）](https://docs.godotengine.org/zh-cn/4.x/tutorials/performance/index.html)、4.7版[CPU优化](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html)及[Server接口](https://docs.godotengine.org/en/4.7/tutorials/performance/using_servers.html)支持连续、批量输入与引擎原生服务；它们不会自动并行本项目的RefCounted规则。共享脚本对象的字段访问也可能抵消并行收益，应量出任务内部访问与交接成本。具体落地方式见计算接入，历史实验见归档。

## 分频、错峰与有界近似（2026-11-11）

不同领域可采用不同的逻辑频率，显示保持连续。频率选择取决于可接受的响应时间和误差；研究中的周期示例不作为项目参数，当前政策见运行合同。

| 实际阅读的一手/作者资料 | 能证明什么，以及不能推断什么 |
|---|---|
| [Factorio FFF421](https://www.factorio.com/blog/post/fff-421)，2024-07-26官方开发日志 | 移动意图和到达时刻支持稀疏机器人更新与连续显示；设施休眠、覆盖分桶。不能推出按机器负载漏算后果是其通用政策 |
| [HugsLib作者的Custom Tick Scheduling](https://github.com/UnlimitedHugs/RimworldHugsLib/wiki/Custom-Tick-Scheduling)，2018/A18资料 | Normal/Rare/Long及同周期调用的均匀分散；是Mod作者对接口与其调度器的说明，不能冒充当前RimWorld全部内部实现 |
| [Cataclysm:DDA map.cpp](https://github.com/CleverRaven/Cataclysm-DDA/blob/master/src/map.cpp)，`map::actualize` | 区域上次时刻支持植物、果实、雨水等累计处理；回合制活动区语义不能原样替代Reol远区后果 |
| [Luanti ABM官方定义](https://api.luanti.org/definition-tables/#abm-activeblockmodifier-definition)、[Minetest Game火焰](https://github.com/luanti-org/minetest_game/blob/master/mods/fire/init.lua) | 环境规则显式选择间隔、概率、离场补偿；火焰显示与传播分开。这是有采样语义的模型，不证明连续物理等价 |
| [Godot 4.7 CPU优化](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html)、[插值介绍](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html) | 降频可减负，插值处理显示阶梯，但低频增加输入延迟；自动物理插值不直接接管Reol自定义提交时钟 |

对Reol的推论：

- 分频减少更新次数，错峰减少同帧峰值，预算续算限制一次阻塞；后两者本身不减少总计算。先查现有due/dirty和响应锚点，避免重复调度。
- 先核对已有采样周期与解析响应；把已经低频的规则改成几秒一次可能反而加重工作，拉大全局请求也可能保留所有内部细步。当前周期只见运行合同，不在研究页重复维护。
- 共同时间不要求每个领域同频物化。优先比较“保留现有内核、领域在采样有效期内合法保持/投影”和“领域异步发布、消费者容忍有限陈旧”两种幅度；完整边界的保护不能直接绕过，后者需要新的依赖语义。
- 慢值何时生效、是否允许遗漏、危险阈值何时升级，应按领域决定。沿路暴露累计有成本，多源主导值和非线性响应也不能只靠求和保持等价。固定分频、按状态适配与按机器负载适配分别影响模型与复现，随机事件不能掩盖它们的区别。

当前频率与模型语义见[运行合同](../../docs/engineering/simulation-pacing.md#领域频率)，性能与误差见BASELINE。研究前的项目上下文见[当日评审提示词快照](../../docs/archive/qa/20261111_multirate_external_review.md)；该快照不持续维护，不作为新计划或基础约束。

### 外部回复11-11-2的复核

用户提供的《建议回复11-11-2.txt》335行已全文阅读。其建议作为候选评估，其中“铁律、严禁、必须”和周期/误差数值没有转为项目约束。以下是实施前的资料复核；后续实测及取舍见BASELINE。

| 可吸收的思路 | 对现有项目的取舍 |
|---|---|
| 直接接触与缓慢场响应分别调度 | 有价值，但按具体效果划分，不能把全部温度/五行一律归为慢过程。接触筛选复用原空间/行动接口，掩码只筛候选；动态生物、范围、遮挡和实际伤害仍要结算。同一效果不能由接触和环境重复收费/扣血 |
| 合并短时间内重复来源/环境拓扑变化 | 优先比较有界周期内的合并与最新源状态，保留旧位置撤销、移除和停止后的唤醒。墙门的通行/阻碍真值与允许延迟的热传播缓存分开，不把全部建筑拓扑一起推迟 |
| 环境候选跨步准备、读取已发布数据 | 可作为窄范围候选；已有GPU异步、取消回收和完整画面投影，新增部分是允许逻辑时间先行及规定场何时生效。先量出收益再增加跨步状态，不复制另一套来源真值 |
| 输入缓冲 | 方向输入与离散操作分别处理，后者可用有界队列。重复方向/目标可合并，执行前复核主体、目标和会话；排队不等于成功受理世界效果，取消/暂停/读档需要明确处理 |
| 已知时间边界的惰性分段、同周期错峰 | 日照等可从共同条件求分段，避免全图同时唤醒；只在输入区间已知、模型可积时等价。植物目前下次采样会对齐公共周期，错峰值得评估，但不是已量出的最大热点 |

需要修正的论证和伪代码：

- **小比例不等于小绝对误差。** `1-exp(-200/30000)=0.00664449`是目标与初值差的比例；差1000℃时约6.644℃，500ms约16.529℃。原热目标映射允许强源；多个短脉冲及反复经过也不能用单次比例保证长期误差。房间重混合还会改变实际初值，不能全部套用单格慢响应界。
- **驻留过滤改变了来源模型。** 快速移动的来源可能始终在同一受体的影响半径内，却从未满足单格驻留阈值；把它整段忽略不等于低误差采样。回复正文提到了移除旧贡献，但示例`dwell_ms < 150: return`没有实现撤销、停止后唤醒或新旧输入排序，不能直接照抄。
- **固定发布时刻与算完就发布是两种政策。** 示例`is_ready()`后用`current_time_ms`采用，会让GPU完成速度影响场生效时刻；可以作为明确接受的近似，但不同时宣称完全复现。若指定逻辑生效点，迟到需选择等待、回退或延后，不可回写已消费的历史。候选依赖也不止拓扑版本，还包括源、基准场及会话；反复作废可能饥饿，旧新两份缓冲本身不解决这些问题。
- **环境有反馈，存档也会受影响。** 人物携源、植物生长/死亡改变源，环境再影响人物和植物，不能概括为天然单向。当前`WorldEnvironmentFieldsState`要求世界与环境时刻一致，并从原对象重建来源；若保存未生效源批/旧场，需改环境保存内容与校验。可复用通用SL管线，但不能承诺只存dirty ID就够、无需任何适配。
- **50ms不是实时保证。** 没有证据保证移出环境后每步4–6ms内完成；也没有证据把每次`pending`当长帧原因。现有插值可继续显示上一段，GPU poll不阻塞宿主。低频、分帧和并行分别解决不同成本，不能用900个世界边界或近乎零pending作为普遍正确出口。
- **其余绝对承诺不采纳。** 纳秒/微秒耗时、95%人物可零延迟求值、误差永远小于1%、收益90%等没有Reol实测。按状态调度本身不证明跨平台确定；概率补偿`1-exp(-λΔt)`只表示固定率下至少一次发生的概率，多次事件/条件变化另需处理。日出日落误差不保证抵消，已知目标段可合并也不因多源max就全部失去价值；方法成本需由实际算法而非统一写成`O(kR²)`判断。

回读原`logs/crowd-release-mixed-300-20261111-111103.json`：最长帧32.880ms内时钟24.724ms、construction帧内累计22.502ms；pending游标已在后续`facility_use`，它不是该帧最大成本。全样本环境阶段累计1585.183ms，服务1870.280ms，人物推进2105.389ms，时钟14248.058ms；这些是旧版带计时样本，环境的同步调用还可能计入其他阶段，不能由此精确算全环境占比。此前公共投影归因也有明显成本，见[历史原记录](../../docs/archive/qa/20261111_performance_experiments.md#人物变化不再清空整个聚落的行动截止点)。现有诊断已有步骤/帧分项，补缺失的发布间隔、输入等待和场新鲜度即可，无需另建监控框架。

回复新增的ONI论据仍有限：[旧Klei运行栈页面](https://kleiforums.com/forums/topic/100036-game-update-297993/page/3/)的搜索摘要能看到`StructureTemperatureComponents.Sim200ms`，本次正文访问403；这不能证明整套底层环境以200ms运行、完全不等待或采用所提双缓冲政策。RimWorld新增内部细节也未核实到指定版本源码，仍以上表已读作者资料支持分频模式，不提升为完整架构证据。

## 成熟项目用了什么

### 用户参考网址逐篇核对（2026-11-11）

已读取`参考资料网址.txt`的19个显式URL及27个不重复的Google引用跳转；跳转解析出补充项目、版本页和文章。重复目标只读一次。原始抓取/解析清单在忽略的`logs/performance-references/inventory.json`，源码固定提交在`source-inventory.json`。外部仓库的CLAUDE.md只作研究资料，不成为Reol指令。

| 资料 / 核对范围 | 有意义的思路与限制 |
|---|---|
| [Vav crowd benchmark](https://github.com/Vav-Labs/godot-crowd-pathfinding-benchmark)，`1b9340a`，README、agent_set、shared_field、scheduler | 同目标共享解、紧凑数组、双缓冲、固定工作量续算、同时量帧时和新解延迟。500/10000/20000人是窄导航负载，不含殖民模拟；基线故意每人每帧A*。源码有无方向时直接趋近目标的演示回退，不能照搬为越墙移动 |
| [配套文章](https://vav-labs.com/blog/moving-10000-agents-in-godot/)及重复README | 延迟也要测：其1536步预算样本新场延迟中位数2150ms；“每帧不卡”不等于行为及时。共享问题先复用答案，再组织调度 |
| [PathForge产品页](https://vav-labs.com/products/pathforge/)及[Vav主页](https://github.com/Vav-Labs) | 多尺寸clearance、局部阻挡与明确失败原因值得借鉴。产品为早期付费候选，页面不是已交付成熟性能证据；不安装或购买 |
| [GodotBoids](https://github.com/Shmupo/GodotBoids)，`94f028f`，V1–V3及SpatialGrid | 空间分桶、同桶共享聚合、MultiMesh。Godot4.2/3D；作者说明V2有时比物理更慢，V3牺牲边界精度；V3桶内分离仍两两比较且未查相邻桶，不能宣传为普遍O(N)。未见明确许可，不复制其代码 |
| [GodotFlowField](https://github.com/TheFamousRat/GodotFlowField)，`0da627f`，README、flowfield结构 | 反向距离场、单向边和通行能力分组。实际是Godot3.2.x的3D/C++ GDNative工程，含OpenMP/RVO依赖，作者也提示性能/错误问题；不是现成Godot4 GDScript插件 |
| [VectorFieldNavigation](https://github.com/D2klaas/Godot-4-VectorFieldNavigation)，`1f266ab`，README、VFNField | 同地图多个权重层、预处理邻接与后台构建。其128²场约130ms是作者硬件样本；共享可变地图不应边写边算，完整场重建也不适合每个细小变化 |
| [gdmapf](https://github.com/nathanfranke-archive/gdmapf)，`3a19071`，README、pathfinding_server_3d | 密度影响代价、共享势场。已归档，作者明确“障碍密集时相向单位卡住”；3D原生扩展，不能作为可靠拥堵解法直接接入 |
| [官方Servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html)，含引用中的4.3版本 | SceneTree可绕过，RID集中管理；资源引用与RID生命周期要自己管理；反复同步回读可能阻塞。4.3语法仅作历史比较，采用API按本项目4.7核对 |
| [官方bullet_shower目录](https://github.com/godotengine/godot-demo-projects/tree/master/2d/bullet_shower)、[README](https://github.com/godotengine/godot-demo-projects/blob/master/2d/bullet_shower/README.md)、[bullets.gd](https://github.com/godotengine/godot-demo-projects/blob/master/2d/bullet_shower/bullets.gd) | 一个循环管理数据和RID，所有子弹共享碰撞形状，一个绘制节点。示例只禁用子弹之间碰撞，仍使用PhysicsServer；不是“高性能必须禁用全部物理” |
| [WorkerThreadPool](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html) | 原生常驻线程池、足量组任务、完成后回收；小任务可能更慢。需要测准备、排队、计算、等待、采用，而非只看kernel |
| [线程安全](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html) | 隔离数据并行、主线程处理场景；同一AStar实例不能多线程同时查询。NavigationServer可并行不代表任意自定义路径对象可共享写 |
| [MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)，含4.6引用页 | 整批buffer、批次按区域拆分、visible_instance_count、shader插值；单实例无独立剔除，人物遮挡/外观/排序不能靠“一次drawcall”自动解决。该教程标有未更新说明，具体API需核对 |
| [CPU优化](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)，含4.5引用页 | 连续访问、减少跨层分派、移除无用工作；原生API与脚本循环区别、线程/语言只在实际热点上选择；冷缓存和限帧影响比较 |
| [通用优化](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html) | 用隔离开关/二分定位，区分持续慢、偶发峰值与初建；先改算法/数据设计，再修局部；计时有开销，瓶颈可能在GPU或驱动等待 |
| [GECS](https://github.com/csprance/gecs)与[CLAUDE.md](https://github.com/csprance/gecs/blob/main/CLAUDE.md)，`8d2d2b2`，archetype/system/command_buffer | 代际句柄、按能力分组、列访问、增量查询缓存、批量结构变更、changed过滤。主README仍写v8安装，CLAUDE含v9升级；Entity仍是Node、Component仍是Resource，不等于纯原生连续数值或免费多核。不引入整套ECS或复制其开发流程 |
| [Arch ECS demo](https://github.com/Neerti/Arch-ECS-Godot-Demo)，README、Systems.cs、EntityRenderer.cs | struct列、InlineParallelQuery、MultiMesh桥接。五万实体只是反弹方块/变色，未承担本游戏规则；C#依赖不是本轮默认技术迁移 |
| [Stagehand](https://github.com/60k41p/Stagehand)，README、rendering_multimesh | Flecs缓存查询、原生系统及批量渲染桥。早期C++ GDExtension，ComputeRenderer明示WIP；不将产品图标当成通用GPU模拟已经成熟 |
| [Rust boids](https://github.com/90-008/godot_boids)，`afa08b9`，README、flock/boid实现 | 原生批计算与Godot桥分开；作者2000/11ms声明明确尚无空间分区，扩展目标4.3。说明语言能改常数，不能消除坏复杂度 |
| [Godex](https://github.com/GodotECS/godex)，`dafb7b0`，README与pipeline布局 | 读写依赖组织系统并行；需要定制引擎构建且绑定旧master，无法当现成4.7 addon直接接入 |
| [gdscript-ecs](https://github.com/yihrmc/gdscript-ecs)，`871ac77`，文档、EcsWorld | 索引ID、能力索引、实体复用及command/event分离；简单组件类并不自动改善数值局部性，查询append实现还有线性去重。可借鉴模式，未见明确许可，不复制代码 |
| [Knightmared原文](https://www.reddit.com/r/Knightmared/comments/1u2as89/godot_4_horde_optimization_hundreds_of_enemies/) | 隔离开关、无帧率上限诊断、分散出生、路径缓存、减少离屏表现；作者明确物理/AI/特效叠加，MultiMesh不能解决逻辑。读取到原帖，未把其他评论当作者结论 |
| [Destroy The Monoliths修正网址](https://radiantslothgames.itch.io/destroy-the-monoliths/devlog/499567/devlog-9-how-to-optimize-your-game-made-with-godot-22) | 原显式网址404，引用跳转给出了有效原文。按需特效、共享Resource、可选池化、移除无用重力/碰撞、低频邻域检查、图形质量设置。原文是3D/旧API；不复制每帧raycast或改变本项目碰撞规则 |

已完成实验由[历史记录](../../docs/archive/qa/20261111_performance_experiments.md)追溯，当前范围只见[主计划](../../docs/plans/foundation-priorities.md)。相近建议合并一次实验；已具备、版本不适配、许可不明或会改变规则的方案说明理由后取其可用原理，不以“都试”要求安装全部框架。

| 一手资料 | 可核实做法 | 对Reol的启发与限制 |
|---|---|---|
| [Factorio FFF421](https://www.factorio.com/blog/post/fff-421)，2024 | 无事的机器人站休眠、事件唤醒；雷达覆盖在chunk登记并共享处理；电网多线程实验受内存吞吐限制 | 不变目标不反复搜索；重叠影响共享索引。雷达是覆盖计数，不能直接代替有强度、半径及次强接替的max场 |
| [Factorio FFF209](https://www.factorio.com/blog/post/fff-209)，2017 | 电网数据按prototype分组；轻量烟雾按chunk集中到连续内存 | 同类定义只解码一次，热循环访问紧凑数值。不能为省内存取消物品独立身份、成本或历史 |
| [Factorio FFF324](https://www.factorio.com/blog/post/fff-324)，2019 | 用事件替代重复检查；热管更新集中到专门管理器，减少不必要的数据访问 | 不只是换公式，还要减少函数分派、字典构造和跨对象读取。其热管机制不能替代本项目已定场规则 |
| [CDDA lightmap源码](https://github.com/CleverRaven/Cataclysm-DDA/blob/06be12f9884d82d387cb6b38dc549eca71c3835a/src/lightmap.cpp#L188-L291) | 按脏子地图重建透明度输入，并使依赖缓存失效 | 变动墙门、来源时精确标记依赖。Reol已有局部失效，增益应落到尚未利用它的路径，不另造第二套缓存 |
| [Mindustry SaveVersion](https://github.com/Anuken/Mindustry/blob/1a22b880576d2f8f97550280f76bfdd0d0069543/core/src/mindustry/io/SaveVersion.java#L213-L291) | 相同地块连续段RLE；多格建筑实体只写一次 | 重复数据无损压缩、实体唯一。植物/家具/材料批次不能被压成丢失状态的地块标签 |
| [OpenTTD存档格式](https://github.com/OpenTTD/OpenTTD/blob/48219078ca6e618d1c25fbec44b6b87daae8f5f8/docs/savegame_format.md)与[保存实现](https://github.com/OpenTTD/OpenTTD/blob/48219078ca6e618d1c25fbec44b6b87daae8f5f8/src/saveload/saveload.cpp#L3046-L3125) | 按域分块、地图位列、对象表；先序列化，再可选后台压缩/写盘 | 领域有自己的紧凑编码；后台写盘不会消除前面的捕获与序列化成本，还需快照内存 |

这些资料核对的是公开开发说明或固定提交的源代码，不是根据玩家帧率反推算法。没有找到足够公开的一手实现来逐项还原《了不起的修仙模拟器》环境内核，不将社区猜测当事实；本轮不复制第三方源码或安装依赖。

## 环境场：怎样减少重复计算

### 1. 将稳定目标与时间响应分开

位置、定义和强度未变时，基础空间分布可以缓存。地块实际温度/五行的建立与消散仍按共同游戏时间求值；不能因基础目标稳定就冻结实际状态。潮汐若能由少量参数与时间查询得到，也不应每帧重新扫描所有实物。

分片只是限制每次工作的长度，不会自动减少总工作量。休眠也必须有可靠唤醒条件：源变更、气候/潮汐阶段、结构修订及已排定的因果事件；远区仍按同一时间规则推进，不以“玩家看不见”取消运算。

### 2. 用局部上界裁剪CPU搜索

仅靠全局通道极值裁剪时，远处格子可能继续搜索一个不可能影响它的强源。可评估每个空间块、每个通道的非零来源及最大强度，再结合到接收格的最近可能距离得到保守上界：整块上界不超过当前最佳值，即可跳过该块。适用前提是保留原距离核；现有实现与覆盖范围查环境合同。

索引应当是权威来源的派生数据，不能只存当前赢家。需要处理同强来源、最后最强来源消失后的次强接替、不同半径、同格多源、跨块覆盖，以及候选排除旧slot/计入新source。若裁剪边界不能证明安全，就保守多算，不能漏算。

这属于本项目的算法推断，不是声称Factorio雷达直接使用了这种求max方法；收益要由访问次数与同负载耗时验证。

### 3. 相同分布可考虑距离变换，但不泛化

若一组来源具有完全相同的强度、半径和单调距离衰减，而且不受墙体路径遮挡，那么该组在一格的最大贡献只取决于最近来源。可先计算最近来源距离，再查原衰减表。学术上的[采样函数距离变换](https://www.theoryofcomputing.org/articles/v008a019/)给出了欧氏距离等特定形式的线性时间算法。

这是有条件的后备方案：来源强度、半径、遮挡或曲线不同就不能直接合为一次最近距离查询；类型/潮汐分组过多也会失去优势。平方距离变换的结论不证明任意径向核都能线性时间求解，不预设它优于局部上界或GPU。

普通FFT卷积求的是加权求和，不能直接替代逐通道max；四邻传播/曼哈顿距离也不等价于欧氏距离。具体通道组合规则只见[环境规则](../rules/environment.md)。

### 4. GPU适合大批基础场，CPU保留小范围更新

[Godot官方compute shader教程](https://docs.godotengine.org/en/4.7/tutorials/shaders/compute_shaders.html)提供RenderingDevice计算路径。Reol已有基础目标GPU及真实3060验证，后续应复用其接口，测来源装配、上传、dispatch、同步/回读和复验的总成本，而非只报compute shader执行时间。

当前CPU块索引与GPU是可分别比较的路线：现有compute shader不会自动读取新CPU块上界。小范围变化可能CPU更划算，大批冷建可能GPU更划算，阈值由实测决定。GPU调度还需明确请求/完成、来源版本、失败回退与取消；不能让缓存一直pending，不能发布过期结果。

CPU/GPU都只产出候选基础场。实际响应、原物变化、共同时间仍由原所有者按同一事件边界联合提交；计算期间呈现最后完整状态。用降低刷新频率掩盖未结算时间、丢弃路径驻留或跳过候选校验都不是等价优化。

## 存读：重点是原世界数据路径

原世界树的重复字段/ID、逐节点Variant分派、编码、校验与I/O可能分别成为热点；不能只根据文件大小选算法。格式与保存管线查当前工程接口，本节仅保留候选方法。

候选优化按实测选择：

- 为稳定、高密度域编码类型化数值列；重复定义/字段用受限数字字典，每个字符串编码一次。类型化编码只改传输表示，不新增物品恢复器，解码仍交原领域所有者做语义校验。
- 优先内置批量缓冲操作，避免脚本逐字节处理。[FileAccess的4.7.2接口](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/FileAccess.xml)有`get_buffer/store_buffer`；Reol已缓冲，不能把“调用批量API”当作尚未存在的修复。
- 确认编码或压缩占优之后，再考虑有限队列流水线。 [Factorio FFF364](https://www.factorio.com/blog/post/fff-364)介绍将大压缩流分成可独立处理部分；线程可以重叠工作，但不会让序列化成本消失。

必须保留长度/计数/类型/引用限制、完整性与末尾校验、在途动作和时间、原账本及幂等回执、独立候选完整验证、失败不改活世界及可发现的中断恢复点。开发验收快照也不能冒称已接入普通游戏存档。

写入统计包含临时档完整重读校验，覆盖旧档还涉及备份/复验；删掉校验得出的“提速”不构成同合同对比。读写并行需要不可变快照和有界缓冲，不能为速度额外制造数份全世界副本。

## 多线程与引擎选择

[Godot线程安全说明](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)要求避免并发修改活场景和共享资源。适合后台任务的是独立纯数据块，完成后确定顺序合并；[FFF364的唤醒队列](https://www.factorio.com/blog/post/fff-364)也展示了共享状态必须延后统一处理。

目标硬件只查基础边界。更多内存可以换缓存和批量缓冲，却不能使每帧全世界扫描变得合理；任务太小、内存带宽或主线程提交占优都会限制多核收益。已有的数据布局需要先核实，避免把早已采用的优化再当成新方案。

建议先在现有Godot/GDScript、内置批处理与已有GPU内验证。只有确认剩余热点确实受脚本执行限制，且算法/布局已合理，才单独评估局部原生实现；引入依赖须另核许可与兼容。用户允许大范围重构，现有class和投入不限制候选；是否扩大重写由实际热路径和实验决定。

2026-11-11经Context7核对4.7官方[物理插值要求](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/using_physics_interpolation.html)：自动插值要求在`_physics_process`内更新变换，帧回调中改变换会抖动。官方[介绍](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html)也说明，独立时刻收到更新时可能更适合自定义插值。Reol当前50ms共同步、可续算和异步提交不是Godot固定物理tick，不能只开启开关替换；可以研究呈现桥或原生动画，但不能用未结算未来补画。

同日核对官方[逐实例uniform](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html#per-instance-uniforms)、[CanvasItem接口](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html#class-canvasitem-method-set-instance-shader-parameter)与[Sprite2D区域UV](https://docs.godotengine.org/en/4.7/classes/class_sprite2d.html#class-sprite2d-property-region-rect)：普通标量/向量可逐实例设置，纹理由材质共享，实例uniform有16项上限；区域精灵的UV仍按整个纹理解释。由此可让同一材质在顶点阶段按已提交整数游戏时间选帧，在片元阶段合成原有贴图层，避免动画每次改变都重放脚本绘图。它属于呈现计算，不接管模拟因果或身体；不能用shader `TIME`推进尚未结算的动作。颜色、层序、干湿、方向和长时间取模要与原画面核对，CPU发布、GPU成本和整局帧时一起决定是否采用，不能以减少draw call直接宣称游戏达标。

## 环境与存读的可选测量思路

这些方向按实际问题选用，不构成测试矩阵或验收清单。比较时保持代码环境与负载一致，可分别观察：

| 环节 | 可观察的成本 |
|---|---|
| 初建 | 原物创建、来源装配、逐通道候选访问/裁剪数、基础场计算、响应激活分别计时 |
| 更新 | 单次累计CPU成本、吞吐、每次分片p95/p99/max、完整发布延迟；分片低尖峰不等于总吞吐足够 |
| GPU | 装配到结果复验端到端时间、上传/回读、显存、CPU回退；与同负载CPU逐通道整数差分 |
| 存读 | 捕获、编码/解析、完整性/语义校验、I/O、原世界stage、派生重建分测；峰工作集/private与文件字节 |
| 正确性 | 同强/次强、跨块/半径、取消/过期、近远和分段时间、在途动作、坏档与完全停开 |

旧初建、保存和GPU测试采用不同分布及计时范围，不可直接算加速倍数；原数值由Git及历史证据追溯。当前验证方式只见[开发循环](../../docs/engineering/workflow/testing.md)。
