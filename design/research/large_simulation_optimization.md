# 大型建造与模拟游戏的性能方法

> 研究资料：记录来源与适用限制，不授予引入依赖或改变规则的权限。

调研：2026-11-06，2026-11-11补充普通300人运行与外部建议的代码对照。范围是运行链、环境场及世界数据；记录来源与适用边界，不改变[环境规则](../rules/environment.md)，也不构成新的任务队列。当前授权、有效测量与实施优先级分别看[接续](../../docs/status/handoff.md)、[BASELINE](../../docs/status/baseline.md)与[主计划](../../docs/plans/foundation-priorities.md)。

## 结论与选型

成熟项目的共同路线是：减少无效工作，组织连续数据，批量处理，再对独立任务并行。分块、休眠、缓存、线程、GPU不是互相替代的万能方案，分别解决不同成本。

普通游戏的首要问题是持续行动负载，而不是存读。11月11日的代码对照和短样本指向：应先重构行动热数据、领域调用与状态发布的执行结构，使主要工作可批量、可并行，并限制局部边界触发的工作范围。详细证据见下一节；当前并未定位全部函数成本，也没有证明某个新布局必然达标。

Reol已有分块、局部失效、packed响应列、分段二进制及基础场GPU实现。大地图初建/存读仍可研究：

1. **基础场初建**：先拆开来源装配和场计算，统计逐通道访问量；对CPU评估局部空间上界/稀疏来源，对GPU评估接入已有基础场计算的完整成本。
2. **大档存读**：先区分编码、解析、校验、I/O和原世界候选恢复；对高重复段评估类型化列、数字字典和批量读写，而非再次宣称“改成二进制”。

这些是按负载选择的研究方向，不替代普通游戏的性能目标。当前没有充分证据把瓶颈归结为Godot引擎上限，也没有依据承诺优化后必然几秒加载。

## 外部卡顿建议与当前代码的对照

2026-11-11阅读用户提供的《其他AI的建议.txt》，只把其中内容视为待核实假设。新普通样本、计数与计时范围见[BASELINE](../../docs/status/baseline.md#外部建议对照样本)；以下代码路径相对于仓库根。

| 建议 | 当前事实 / 怎样使用 |
|---|---|
| 模拟与SceneTree解耦、集中管理 | `VillageSimulation`、`RegionalSimulation`、`SimLocalMotion`已为RefCounted；NPC的`Pawn`为Node2D视图。玩家根节点虽为CharacterBody2D，当前移动没有调用move_and_slide。不能重复建设另一个SimulationManager；应评估由紧凑热数据直接持有原事实，减少字典到worker再逐项写回的搬运 |
| 空间哈希替代全体两两比较 | `SimWorldSpace`已有按格查询，结构/植物等也有索引；当前行走并不是示例里的每帧全体软排斥。若现有索引粒度或代价不合适就替换其实现，不再为相同事实新增一套通用登记 |
| 分帧、休眠、懒计算 | 已有共同钟、预算续算、ParticipationIndex及身体按需积分。要检查局部到期为何仍进入完整领域链、哪些投影查询要求同步身体；仅增加第二个预算队列不会减少总工作 |
| WorkerThreadPool | 已真实采用，但当前批只覆盖需求/体力及路段插值；同时到期不足64人的工作仍直接执行，错开的到期时刻难以形成大批。重点是扩大独立计算覆盖的实际成本、减少准备/采用开销，不是继续调线程数量 |
| 寻路节流、连通域、流场 | 路径已存于行动，开始/修路时才请求。短探针的完整寻路成本很低，不能把它预定为当前第一瓶颈；不可达/拥挤场景另论。连通域必须对应通行能力、门及动态结构，房间编号不同不能直接判定无路。流场适用于大量单位共享目的地，不是所有工作寻路的替代 |
| GPU密集数学 | 已有环境基础场GPU服务，现已实际接入普通来源候选并由原owner采用。仍需比较装配、异步等待、计算与采用的端到端收益；CPU/GPU批处理与减少无效工作可以同时推进。Compute Shader不是任意GDScript或共享世界操作的自动加速器 |
| C# / GDExtension、移除全部物理 | 局部原生热点可以评估，不能用无出处的语言倍数或单位上限作选型。当前没有引入新语言/插件；未来投射物、接触检测等仍可使用适合的Godot原生能力，无须因格子游戏而全盘禁止物理 |

本次最需要带进实施的结论是**并行覆盖范围与调用放大**：原行动仍是已计时kernel中最大项，状态发布和kernel外围也占有明显成本；短探针显示控制查询远多于完整寻路，但该查询不是全部瓶颈。下一次行动重构应沿主计划A/B，把局部输入准备、活动执行、依赖变更和已提交投影放在同一条热数据链上，减少跨领域重复读取，形成有分量的独立CPU工作；不要只把几个加减法搬进线程池。

稳定路段可以按已受理的起点/速度/时间直接求位置，在抵达或真实依赖变化时执行后果；有环境来源、阻碍、交互依赖的过格子仍须保留相应因果。可见性只决定表现工作，不能让离屏战斗突然换成另一套胜负规则。现有`SimRouteTravel.projected_point`已支持路段投影，重点是哪些调用仍反复物化身体或扩大唤醒范围。

外部示例的墙钟3ms循环、`Engine.get_process_frames() % 10`或“其余单位沿用旧速度”不能直接充当世界规则：不同机器完成数量不同，若据此决定作用时刻就改变因果。预算只决定何时继续计算；到期时刻、同刻顺序和依赖仍来自逻辑时间。只在一次调用后检查预算，也无法抢占一个本身超过预算的长函数。

再次核对的一手经验是[Factorio FFF421](https://www.factorio.com/blog/post/fff-421)：机器人记录移动意图及下次更新时间，渲染平滑显示；其独立读计算有多线程收益，电网多线程实验则未改善整体速度。应同时借鉴活动选择、数据组织与并行覆盖，不能只截取其中一个成功倍数。[Godot线程池说明](https://docs.godotengine.org/en/4.7/classes/class_workerthreadpool.html)提示小任务可能变慢；[线程安全说明](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)明确同一AStar实例不能被多个线程同时查询；[compute教程](https://docs.godotengine.org/en/4.7/tutorials/shaders/compute_shaders.html)提示立即sync会让CPU等GPU。这些限制决定任务怎样拆，并不否定采用多核/GPU。

外部建议中的“耗时直接除以核数”“几百人必能在1ms内完成”“改完必涨5–10倍”缺少同负载证据，不采作容量承诺。Packed数组改善存储与批量接口，但不会把脚本逐项循环自动变为原生SIMD。首轮对照仅是诊断，后续实际采用与撤回结果统一见BASELINE，不能以本页的早期假设覆盖后续证据。

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

全部可执行思路已收敛到[主计划实验清单](../../docs/plans/foundation-priorities.md#参考资料驱动的实验清单2026-11-11)。相近建议合并一次实验；已具备、版本不适配、许可不明或会改变规则的方案说明理由后取其可用原理，不以“都试”要求安装全部框架。

| 一手资料 | 可核实做法 | 对Reol的启发与限制 |
|---|---|---|
| [Factorio FFF421](https://www.factorio.com/blog/post/fff-421)，2024 | 无事的机器人站休眠、事件唤醒；雷达覆盖在chunk登记并共享处理；电网多线程实验受内存吞吐限制 | 不变目标不反复搜索；重叠影响共享索引。雷达是覆盖计数，不能直接代替有强度、半径及次强接替的max场 |
| [Factorio FFF209](https://www.factorio.com/blog/post/fff-209)，2017 | 电网数据按prototype分组；轻量烟雾按chunk集中到连续内存 | 同类定义只解码一次，热循环访问紧凑数值。不能为省内存取消物品独立身份、成本或历史 |
| [Factorio FFF324](https://www.factorio.com/blog/post/fff-324)，2019 | 用事件替代重复检查；热管更新集中到专门管理器，减少不必要的数据访问 | 不只是换公式，还要减少函数分派、字典构造和跨对象读取。其热管机制不能替代本项目已定场规则 |
| [CDDA lightmap源码](https://github.com/CleverRaven/Cataclysm-DDA/blob/06be12f9884d82d387cb6b38dc549eca71c3835a/src/lightmap.cpp#L188-L291) | 按脏子地图重建透明度输入，并使依赖缓存失效 | 变动墙门、来源时精确标记依赖。Reol已有局部失效，增益应落到尚未利用它的路径，不另造第二套缓存 |
| [Mindustry SaveVersion](https://github.com/Anuken/Mindustry/blob/1a22b880576d2f8f97550280f76bfdd0d0069543/core/src/mindustry/io/SaveVersion.java#L213-L291) | 相同地块连续段RLE；多格建筑实体只写一次 | 重复数据无损压缩、实体唯一。植物/家具/材料批次不能被压成丢失状态的地块标签 |
| [OpenTTD存档格式](https://github.com/OpenTTD/OpenTTD/blob/48219078ca6e618d1c25fbec44b6b87daae8f5f8/docs/savegame_format.md)与[保存实现](https://github.com/OpenTTD/OpenTTD/blob/48219078ca6e618d1c25fbec44b6b87daae8f5f8/src/saveload/saveload.cpp#L3046-L3125) | 按域分块、地图位列、对象表；先序列化，再可选后台压缩/写盘 | 领域有自己的紧凑编码；后台写盘不会消除前面的捕获与序列化成本，还需快照内存 |

这些资料核对的是公开开发说明或固定提交的源代码，不是根据玩家帧率反推算法。没有找到足够公开的一手实现来逐项还原《了不起的修仙模拟器》环境内核，不将社区猜测当事实；本轮不复制第三方源码或安装依赖。

## 外部回复的架构复核（2026-11-11）

用户提供`建议回复11-11.txt`，全文348行已读。它基于项目快照、未看源码；其中删除/改写清单是候选，不是新的项目指令。以下只维护新增判断，实施顺序归[主计划](../../docs/plans/foundation-priorities.md#外部建议后的下一组判别2026-11-11)。

| 建议 | 可吸收部分 | 核对后的限制 |
|---|---|---|
| 先查流速与框架开销 | 将准入容量、每帧预算、边界准备、续算、公共发布分别测；避免宿主帧间隔反馈无谓压低吞吐 | 15.205秒是时钟回调墙时，不是完整进程CPU；平均空闲不能证明每帧余量。原式`帧秒×us/游戏ms×倍率×1000游戏ms/秒`量纲为us/帧，并非量纲错误。120/240差异不能单独证明算法错误 |
| 固定宏步、事件缓冲 | 批量收集相同时刻变化，局部事件不必让所有领域重新准备；逻辑顺序与宿主执行解耦 | 当前外层本来是50ms，内部含必要因果边界；约3700回调还包含续算，须另数真实边界。区间内封门、死亡、取消可使后续候选失效，事后排序不自动等价；只用终点会漏途中环境驻留 |
| 统一运动权威与SoA | native/服务/施工/行旅可共用几何、跨格缓冲和抵达令牌；持续热列避免打包回写 | 原局部迁移不能证明全面数据重构无用，也不能据猜测断言它只是包装RefCounted。ID不能随数组压缩/复用而串人，Float32会改变精度；不另建一份权威位置 |
| 静态/动态max场拆分 | 对同一时刻，`max(静态,动态)`逐通道严格成立；移动源可避免重复求静态来源。局部来源清单/前向投射值得测 | 仍要结清每个输入段；Top-2连续删除后需回退找其余来源。块清单应按几何超覆盖登记，不能只含当前透过率非零的源，否则开门漏源。当前冷场已共享局部来源，温度也已有解析锚点，不能重复建设 |
| CPU小更新、GPU大批；只并行大任务 | 比较准备、派发、等待、采用全链路；现有CLI已能比较CPU/GPU及身体worker | 4096格、300人0.15ms、动态源0.1ms、50ms步2–4ms和C++十倍/千人均未实测，不能据此直接删后端。原场是带遮挡逐通道max，不能无条件替换CDDA算法 |
| 精简引擎边界和压测 | 原生呈现继续，先查重复投影；区分自然完成与主动打断，输入按逻辑时刻可复现 | 网格索引O(1)不证明扫掠/碰撞/寻路全问题比Godot快百倍；不新增永久禁用PhysicsServer/NavigationServer规则。现巡行是抵达后主动取消工作再巡行，并非误取消已结束动作；该命令压力要单列 |

重新核对[Fix Your Timestep](https://gafferongames.com/post/fix_your_timestep/)：固定逻辑步/显示分离、留余量及限制每帧追赶支持上述方向，但不承诺一个50ms逻辑步的计算必能塞进16.67ms画面帧，也不证明能删掉所有续算。[Godot WorkerThreadPool](https://docs.godotengine.org/en/4.7/classes/class_workerthreadpool.html)明确小计算任务可能更慢；它支持按粒度测量，不支持凭人数一律关闭。未找到可核对的一手材料证明回复中的“50ms延迟就是RimWorld/Factorio标准等价做法”。

## 环境场：怎样减少重复计算

### 1. 将稳定目标与时间响应分开

位置、定义和强度未变时，基础空间分布可以缓存。地块实际温度/五行的建立与消散仍按共同游戏时间求值；不能因基础目标稳定就冻结实际状态。潮汐若能由少量参数与时间查询得到，也不应每帧重新扫描所有实物。

分片只是限制每次工作的长度，不会自动减少总工作量。休眠也必须有可靠唤醒条件：源变更、气候/潮汐阶段、结构修订及已排定的因果事件；远区仍按同一时间规则推进，不以“玩家看不见”取消运算。

### 2. 用局部上界裁剪CPU搜索

当前全局通道极值会让远处格子继续搜索一个不可能影响它的强源。建议评估每个空间块、每个通道的非零来源及最大强度，再结合到接收格的最近可能距离得到保守上界：整块上界不超过当前最佳值，即可跳过该块。圆形半径和原整数距离核保持不变。

索引应当是权威来源的派生数据，不能只存当前赢家。需要处理同强来源、最后最强来源消失后的次强接替、不同半径、同格多源、跨块覆盖，以及候选排除旧slot/计入新source。若裁剪边界不能证明安全，就保守多算，不能漏算。

这属于本项目的算法推断，不是声称Factorio雷达直接使用了这种求max方法；收益要由访问次数与同负载耗时验证。

### 3. 相同分布可考虑距离变换，但不泛化

若一组来源具有完全相同的强度、半径和单调距离衰减，而且不受墙体路径遮挡，那么该组在一格的最大贡献只取决于最近来源。可先计算最近来源距离，再查原衰减表。学术上的[采样函数距离变换](https://www.theoryofcomputing.org/articles/v008a019/)给出了欧氏距离等特定形式的线性时间算法。

这是有条件的后备方案：来源强度、半径、遮挡或曲线不同就不能直接合为一次最近距离查询；类型/潮汐分组过多也会失去优势。平方距离变换的结论不证明任意径向核都能线性时间求解。当前优先比较局部上界和已有GPU，不先引入一套复杂变换。

普通FFT卷积求的是加权求和，不能直接替代逐通道max；四邻传播/曼哈顿距离也不能悄悄替换当前欧氏距离。五行独立取max，冷热各自取max后相减，同类堆数量不放大，这些规则不为性能而改变。

### 4. GPU适合大批基础场，CPU保留小范围更新

[Godot官方compute shader教程](https://docs.godotengine.org/en/4.7/tutorials/shaders/compute_shaders.html)提供RenderingDevice计算路径。Reol已有基础目标GPU及真实3060验证，后续应复用其接口，测来源装配、上传、dispatch、同步/回读和复验的总成本，而非只报compute shader执行时间。

当前CPU块索引与GPU是可分别比较的路线：现有compute shader不会自动读取新CPU块上界。小范围变化可能CPU更划算，大批冷建可能GPU更划算，阈值由实测决定。GPU调度还需明确请求/完成、来源版本、失败回退与取消；不能让缓存一直pending，不能发布过期结果。

CPU/GPU都只产出候选基础场。实际响应、原物变化、共同时间仍由原所有者按同一事件边界联合提交；计算期间呈现最后完整状态。用降低刷新频率掩盖未结算时间、丢弃路径驻留或跳过候选校验都不是等价优化。

## 存读：重点是原世界数据路径

现有文件已经是分段二进制，响应也已使用packed列。下一步应剖析高重复的原世界树：逐节点字典/Variant分派、相同字段名/ID的反复UTF-8处理、完整性验证与文件I/O各占多少。

候选优化按实测选择：

- 为稳定、高密度域编码类型化数值列；重复定义/字段用受限数字字典，每个字符串编码一次。类型化编码只改传输表示，不新增物品恢复器，解码仍交原领域所有者做语义校验。
- 优先内置批量缓冲操作，避免脚本逐字节处理。[FileAccess的4.7.2接口](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/FileAccess.xml)有`get_buffer/store_buffer`；Reol已缓冲，不能把“调用批量API”当作尚未存在的修复。
- 确认编码或压缩占优之后，再考虑有限队列流水线。 [Factorio FFF364](https://www.factorio.com/blog/post/fff-364)介绍将大压缩流分成可独立处理部分；线程可以重叠工作，但不会让序列化成本消失。

必须保留长度/计数/类型/引用限制、完整性与末尾校验、在途动作和时间、原账本及幂等回执、独立候选完整验证、失败不改活世界及可发现的中断恢复点。开发验收快照也不能冒称已接入普通游戏存档。

写入统计包含临时档完整重读校验，覆盖旧档还涉及备份/复验；删掉校验得出的“提速”不构成同合同对比。读写并行需要不可变快照和有界缓冲，不能为速度额外制造数份全世界副本。

## 多线程与引擎选择

[Godot线程安全说明](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)要求避免并发修改活场景和共享资源。适合后台任务的是独立纯数据块，完成后确定顺序合并；[FFF364的唤醒队列](https://www.factorio.com/blog/post/fff-364)也展示了共享状态必须延后统一处理。

16GB整机、单RTX3060仍是目标；更多内存可以换缓存和批量缓冲，却不能使每帧全世界扫描变得合理。线程数也不等于速度倍数：任务太小、内存带宽或主线程提交占优都会限制收益。Reol模拟已不依赖每物品一个Node，不能把“去掉海量节点”包装为本轮新成果。

建议先在现有Godot/GDScript、内置批处理与已有GPU内验证。只有确认剩余热点确实受脚本执行限制，且算法/布局已合理，才单独评估局部原生实现；引入依赖须另核许可与兼容。用户允许大范围重构，现有class和投入不限制候选；是否扩大重写由实际热路径和实验决定。

2026-11-11经Context7核对4.7官方[物理插值要求](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/using_physics_interpolation.html)：自动插值要求在`_physics_process`内更新变换，帧回调中改变换会抖动。官方[介绍](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html)也说明，独立时刻收到更新时可能更适合自定义插值。Reol当前50ms共同步、可续算和异步提交不是Godot固定物理tick，不能只开启开关替换；可以研究呈现桥或原生动画，但不能用未结算未来补画。

同日核对官方[逐实例uniform](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html#per-instance-uniforms)、[CanvasItem接口](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html#class-canvasitem-method-set-instance-shader-parameter)与[Sprite2D区域UV](https://docs.godotengine.org/en/4.7/classes/class_sprite2d.html#class-sprite2d-property-region-rect)：普通标量/向量可逐实例设置，纹理由材质共享，实例uniform有16项上限；区域精灵的UV仍按整个纹理解释。由此可让同一材质在顶点阶段按已提交整数游戏时间选帧，在片元阶段合成原有贴图层，避免动画每次改变都重放脚本绘图。它属于呈现计算，不接管模拟因果或身体；不能用shader `TIME`推进尚未结算的动作。颜色、层序、干湿、方向和长时间取模要与原画面核对，CPU发布、GPU成本和整局帧时一起决定是否采用，不能以减少draw call直接宣称游戏达标。

## 环境与存读专项怎样测量

先用同一代码环境、预算与负载测64²/128²，确认瓶颈后再跑512²；区分静态满密度、单稀有极值、多件同强极值、混合半径及批量变化，不能只优化一种石头案例。记录：

| 环节 | 必需指标 |
|---|---|
| 初建 | 原物创建、来源装配、逐通道候选访问/裁剪数、基础场计算、响应激活分别计时 |
| 更新 | 单次累计CPU成本、吞吐、每次分片p95/p99/max、完整发布延迟；分片低尖峰不等于总吞吐足够 |
| GPU | 装配到结果复验端到端时间、上传/回读、显存、CPU回退；与同负载CPU逐通道整数差分 |
| 存读 | 捕获、编码/解析、完整性/语义校验、I/O、原世界stage、派生重建分测；峰工作集/private与文件字节 |
| 正确性 | 同强/次强、跨块/半径、取消/过期、近远和分段时间、在途动作、坏档与完全停开 |

上轮确已测出初建与加载很慢，但550.9秒的`sources`包括装配和CPU基础缓存；217.8MB文件的137.3秒写入包括完整重读校验。旧GPU0.616秒属于不同分布和计时范围，不能据此承诺新路径几百倍加速。甚至更接近的旧响应负载与新负载也存在预算和运行环境差异，需重新建立同条件分项基线。

以上专项矩阵属于11月6日研究的可选测量，不是当前开发门禁。11月11日只运行普通300人短样本及临时调用探针，未重跑这些专项；当前测量方式见[开发循环](../../docs/engineering/workflow/testing.md)，不恢复旧回归。
