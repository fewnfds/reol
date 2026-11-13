# 大型模拟运行框架：一手研究与本轮裁决

研究更新：2026-11-13。这里记录可核查来源、适用边界与顾问取舍；不是第二计划。当前接口、能力与实测分别只查[架构](../../docs/engineering/architecture.md)、[FEATURES](../../docs/status/features.md)、[BASELINE](../../docs/status/baseline.md)。旧实现由Git的a493bf0追溯。

## 本轮先证实了什么

旧release千人场景在请求1/2/4倍时实际均约0.9倍，降低到30FPS反而跌至约0.77倍。源码显示每50ms需要把活世界借回主线程，处理UI/画布/时钟通知后再提交下一步；普通跨格又切出多个全域边界。关闭自适应减速也没突破容量。

这不能仅凭一个40ms平均步耗时推导硬件极限，也不能把所有未归因成本说成字典或单核。旧压力驱动器还会到站取消工作、触发额外观察/失效，其成本与真实领域规则要分开。当前新切片主动删除了多项旧玩法，吞吐不代表原全玩法逐位等价。

## 成熟项目与引擎：实际核查到的经验

本轮直接下载并读过15份官方文章/源码，原件和SHA留在本机顾问目录；下面链接供复核，不提交第三方源码副本。

| 一手来源 | 可证实的设计与边界 | 本轮采用/避免 |
|---|---|---|
| Factorio [FFF70](https://www.factorio.com/blog/post/fff-70)、[FFF150](https://www.factorio.com/blog/post/fff-150) | 更新、准备、绘制有不同责任；可以减少绘制维持模拟更新，准备仍有同步条件；更新本身过载仍有UPS上限 | 消除每步等画面收取，不承诺任意负载始终维持4倍 |
| Factorio [FFF421](https://www.factorio.com/blog/post/fff-421) | 静态/休眠对象避免每tick无用更新；具体改动的收益依赖实际对象行为 | 静态地形画布和静态环境不每步重建；不照搬其收益数字 |
| [OpenRA Game.cs](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Game/Game.cs)、[World.cs](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Game/World.cs) | LogicTick、RenderTick和世界tick职责清楚；普通游玩路径仍包含logic后必须render的约束 | 借鉴责任划分，不把它说成完全没有显示/模拟耦合的现成模板 |
| Mindustry [AsyncCore](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/async/AsyncCore.java)、[PhysicsProcess](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/async/PhysicsProcess.java)、[Logic](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/core/Logic.java) | begin/process/end有join；物理任务按不相互作用的碰撞层并行 | 按独立页/结果并行，避免每个领域一个自由推进线程 |
| [OpenTTD 主循环](https://github.com/OpenTTD/OpenTTD/blob/master/src/openttd.cpp) | 车辆、地块、脚本等在游戏循环内各有职责/周期；不是所有东西每画面帧调用 | 保留共同时间但按领域频率唤醒，普通移动不强迫慢环境结算 |
| [OpenRCT2 Context](https://github.com/OpenRCT2/OpenRCT2/blob/develop/src/openrct2/Context.cpp) | 游戏更新累加器可在一次绘制前执行多次更新，插值与权威位置分开 | 倍率完成更多相同步；画面只使用已提交位置，不伪造未来 |
| Veloren [state.rs](https://github.com/veloren/veloren/blob/master/common/state/src/state.rs)、[server](https://github.com/veloren/veloren/blob/master/server/src/lib.rs) | Dispatcher调度并行系统，维护实体结构与本地事件采用有明确阶段 | 并行独占身体页，跨单位/资源效果由owner采用；不照抄其Rust/ECS开销 |
| [Flecs Systems](https://github.com/SanderMertens/flecs/blob/master/docs/Systems.md) | staged结构变化、worker切片与immediate单线程系统有不同限制 | 不把ECS当万能提速器，不为低频业务强制表迁移/批接口 |
| [RimWorld官方公告](https://store.steampowered.com/news/app/294100)、[Ludeon](https://ludeon.com/blog/) | 官方1.6说明寻路批处理/多线程及光照多线程，1.7说明Waylith引擎迁移；闭源内部完整调度并未公开 | 成熟项目也会针对瓶颈重构；不能据公告推断其所有Pawn逻辑、GPU模型或照搬内部class |
| Godot [线程安全](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)、[WorkerThreadPool](https://docs.godotengine.org/en/4.7/classes/class_workerthreadpool.html) | 活SceneTree不能任意多线程访问；任务量不足时调度可能负收益 | 不碰场景的独占页批；引擎管理池，不自造每域线程池 |
| Godot [PackedVector2Array](https://docs.godotengine.org/en/4.7/classes/class_packedvector2array.html)、[C++ core types](https://docs.godotengine.org/en/4.7/tutorials/scripting/cpp/core_types.html)、[cowdata.h](https://github.com/godotengine/godot/blob/4.7/core/templates/cowdata.h) | GDScript Packed数组是引用值，需要duplicate/新目标拷贝才能独立；C++容器的CoW不能证明脚本共享写安全 | 生产者新建脱离Frame，发布后不写；保留旧帧不导致槽位覆盖 |

## 官方性能指南逐篇核查

之前完整阅读了用户指定[performance目录](https://docs.godotengine.org/en/4.7/tutorials/performance/index.html)，本轮用新架构重新解释适用性。不是要求每篇教程都实现一个模块。

| 官方子篇 | 当前结论 |
|---|---|
| [General optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/general_optimization.html) | 测量端到端、区分装配与稳态；只保留真实收益，不用短smoke代替容量 |
| [Using servers](https://docs.godotengine.org/en/4.7/tutorials/performance/using_servers.html) | 逻辑为纯数据；绘制使用Godot原生MultiMesh，不重写通用渲染器 |
| [CPU optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html) | 连续热列、局部缓存、避免大量小对象/跨格广播；低频逻辑仍可简单直接写 |
| [GPU optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/gpu_optimization.html) | GPU绘制与compute回读是不同成本。当前删除小批CPU必等的GPU逻辑场，保留显示GPU数学 |
| [Using MultiMesh](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html) | 同类人物原生批绘；当前不提供完整y排序/多层装备，不能宣传与旧外观完全等价 |
| [Using multiple threads](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multiple_threads.html) | 一个自主模拟线程，独立页批处理；命令/通知与只读快照交换，不借还活世界 |
| [Thread-safe APIs](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html) | 共享容器不并发变长；同一个Packed引用不并发写；场景/资源操作留主线程 |
| [Optimizing 3D performance](https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html) | 当前为2D，不引入GI/3D遮挡/网格LOD；只借鉴分块裁剪与共享资源思想 |
| [Vertex animation目录](https://docs.godotengine.org/en/4.7/tutorials/performance/vertex_animation/index.html) | 视觉变形/动画可以留GPU；不能把显示控制点当真实身体事实 |
| [Controlling thousands of fish](https://docs.godotengine.org/en/4.7/tutorials/performance/vertex_animation/controlling_thousands_of_fish.html) | 群体控制适合装饰实例；NPC仍保留各自实际路线、资源和后果 |
| [Animation of thousands of objects](https://docs.godotengine.org/en/4.7/tutorials/performance/vertex_animation/animating_thousands_of_fish.html) | 采用实例数据+GPU动画思想；脚点和朝向仍来自真实单位数据 |
| [Pipeline compilations](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html) | 装配/首次图集shader预热与稳态分开，不用预热掩盖持续模拟成本 |
| [Background loading](https://docs.godotengine.org/en/4.7/tutorials/io/background_loading.html) | 当前有限切片未恢复分块加载；将来异步资源准备不应获取活世界的全局锁 |

Background loading是相关补充，不属于原performance目录。MultiMesh/鱼群篇标记旧版的示例仅借用思想，实际API按4.7核对。官方目录随版本变化；本文针对实际4.7，不假装其给出了本游戏通用插件或无限人口承诺。

## 九次顾问咨询如何取舍

六路独立研究分别覆盖架构、线程、运动、环境、成熟项目与测量；另三路拿到新原型源码审查线程、因果和验收。全部非流式、65536输出预算、正常stop结束；原回答不上传，模型观点由源码/短反例/实机验证决定。

| 采用并核查 | 未采用或纠正 |
|---|---|
| 自主模拟、窄显示值、连续页、共享效果由owner提交 | 天真三缓冲槽位复用、强制无锁、每域一线程；没有必要为形式替换简单引用邮箱 |
| 静态场缓存、移动源接收端求值、房间单状态、删除无人空地响应历史 | 未经确认把max改成sum、固定三点射线假称不会漏薄墙、把旧场说成PDE |
| 原生AStarGrid、私有lane缓存、按需失效在途路线 | “所有路径3秒后全命中”的推断：实际采样窗仍记录新寻路，现已补delta |
| 短位置历史用于低FPS高倍速插值，可靠结果不跟快照丢弃 | 用最后两个已采用帧直线插值可能切掉中间拐弯；当前保留相邻已提交姿态选择 |
| 热伤害放在本步更早到期/到达效果之后；送货遇阻保留货物并换仓；建造保留未改变房间热历史 | 顾问把方向函数的5度迟滞误读为5像素阈值；不据此改朝向规则 |
| 初始环境数值、死亡源移除、关闭未执行命令有明确取消回执、合并唤醒令牌 | 把按旧倍率累计至控制采用边界认作必然竞态；该区间语义本来成立，另修初始化锁与暂停债务 |
| 窗口只统计实际步/路径增量、帧龄、资源与真实交付 | 仅因某个原型慢于任意阈值，就证明GDScript字节码是极限并自动引入C++ |

顾问多处给出未经测量的百分比收益、原生耗时、工期、RimWorld/Veloren内部细节或错误文章编号，均未作为事实采用。GDScript新切片已能证明本阶段容量，因此目前不引入C#、原生扩展、外部ECS或全GPU模拟；未来真实密集算子仍可按证据评估。

## 削减与剩余边界

重建初版删除全域亚步、活世界借还/信号重接、每步画布重建和原GPU场回读，并先削减玩法建立容量出口。后续六段功能恢复已在同一内核重做实物/SL、生活、植物、战斗、交往修行和有限地区；当前未实现边界只查FEATURES，旧删减列表不再作当前事实。

动态建造仍有冷路径围合和必要静态场重建；已加入索敌/弹道与施工混合短窗，密集全图施工、极大半径、不同硬件和长局仍需各自测量。这里不继续生成一份无限优化任务队列；是否扩展由唯一主计划与新需求决定。

## 功能恢复的依赖核查

2026-11-12另做两路咨询，分别从玩家体验和实际代码依赖审视添加顺序；均为非流式、65536输出预算、正常stop结束。原问题、回答和逐项核查留本机`feature-return-20261112`，此处只记录影响决定的依据，实际顺序仍只看主计划。

制定添加顺序时的初版切片（db78f4c）存在这些缺口：人物ID直接推导页行，事件按`time * 65536 + id`打包，`cargo`/`stored`是标量，墙门与资源无一般对象实例，NPC走固定循环。后续已按实际闭环替换，现行解释只查架构页。先在可玩的取放场景中恢复身份、实物归属、中断和存读，能为之后建筑、植物与战斗提供共同基础；这些缺口不证明必须采用顾问指定的64位编码、槽位复用方式或万能实体表。

| 本轮取舍 | 依据与限制 |
|---|---|
| 采用定义/实例分离，提前恢复存读接缝 | Factorio [FFF259](https://www.factorio.com/blog/post/fff-259)解释的是**prototype定义**的名称/整数映射，不是运行实例ID算法；[FFF270](https://www.factorio.com/blog/post/fff-270)说明保存映射和地图、加载时处理引用与依赖。借鉴状态完整性，不搬入其多人/回放的全局确定性与旧格式迁移要求 |
| 按原状态导出需要保存的值 | Godot[存读教程](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html)让持久对象给出自己的数据，提供FileAccess和序列化机制。Persist组的场景示例不是自主模拟世界的现成完整SL；具体owner捕获、候选校验和接续仍由项目处理 |
| 动态、静态与低频对象选择合适表示 | 同一可寻址身份不意味着同一每步处理成本；墙/箱无需身体移动页，量物可堆叠，个体器物保留独有状态。当前后端与Godot线程边界支持这种分工，不强制每个字段SoA或新建领域线程 |
| 缩小首段，认识随实际交互加入 | 顾问首段曾包含建屋、衣着、雨天、煮饭与御寒，且两答对认识与战斗顺序不同。采用先交付取放/接续，再扩生活的安排；基础找物不先写成全知，社会传播可以后补。不因同模型两答相似就视为独立实证 |
| 拒绝无依据的参数与一刀切方案 | 不采用固定32×32窗口必能修复围合、任意分片必保持低频过程语义、“300–500行即可完成”、假定几乎零成本或未经测量的耗时门槛。结构影响范围要随真实拓扑判断，性能随实际新增负载验证 |
| 保留用户已定的开发体验与工程选择空间 | 不采用把默认真实数值换成体感文字、仅跨格刷新迷雾或门需开关才围合的建议；也不采用禁止Godot物理或规定顾问只能找Bug的绝对禁令。顾问适合发散方案和提反例，具体API、来源与收益仍需核查 |

两答仍大量复述历史样本、给出未验证性能/工期，并列出未逐一确认的游戏内部实现与文章编号；这些未升级为项目事实。当前万人结果仍只代表已测的缩减切片，不成为功能恢复的全玩法人口门槛。这两次规划咨询本身没有新增代码；其后的恢复成果与同包测量已登记FEATURES、BASELINE，不继续沿用当时的删减状态。

## 实物与生活恢复的顾问核查

第1、2段方案、反例及源码review共六路，另第3段设计已收；非流式，原问答在本机restore-play目录。首段源码review一次65536预算被思考占满而length截断，不称为完整审查；后续聚焦问题用131072预算、medium思考。最终取舍：

- 采用共同接近/到期/取消过程、真实物资与结构材料分开、步末合并拓扑、个人观察库存副本、到达后刷新线索、寻路失败唤回自主生活、多格跨桶索引、UI命令附显示会话epoch。以上以源码及短反例核对。
- 箱子取放不应像床/工作台独占。途中预约箱子使窗内交付从千级降至105次，撤回后5456次；取放并发计时、完成时owner原子转移。不是所有共享对象都需要同一排它语义。
- 观察保留任意物品类别，按库存版本复用未变化快照，没有采纳只保存wood/meal字段的窄优化；维护认识与事实分离。
- 顾问两次称Godot跨平台禁止rename覆盖；本机4.7.2创建A/B后rename(A,B)返回OK、目标内容更新，多次短检查也能连续写同一档，故拒绝其无依据的“必失败”。顾问把lane当常驻Thread也是错误：它是WorkerThreadPool批上下文，step结束已join，没有待关闭的lane线程。
- 顾问以锁60FPS下16.7ms帧P99推断owner计算接近极限、给出90%分配节省/15–25%耗时收益，均无实测依据。显示与owner已经解耦，计算成本、实际倍率和交付量分别看BASELINE。

随后植物已采用低频分组采样与来源变化局部更新；不采纳“5秒抽检必定捕捉4秒经过”的错误保证，不把成精等同于Monster继承或强制植物占移动页。实际精度只查simulation-pacing。


## 自然、战斗、交往与地区的集成核查

第3–6段分别做设计发散与实际代码审查，另有感知与最终跨域审查，多次非流式咨询留在本机restore-play目录；聚焦review使用131072输出预算。顾问不是批准门禁，也没有把其标注的P0/P1直接当作事实。

| 采用并核实 | 拒绝、限定或纠正 |
|---|---|
| 植物独立对象、宿主关系、分组采样、局部max来源回填 | 不承诺捕捉短于采样周期的所有经过；不把来源属性和物理发热自动画等号 |
| 共用动作完成时复核成熟/容量，先验产物容量再提交 | 不对幼苗砍伐白得种子与树桩；不把预先同意交互等同于条件永不改变；枯树不能领取修行收益 |
| 战斗用[Geometry2D](https://docs.godotengine.org/en/4.7/classes/class_geometry2d.html)线段/圆几何，活跃集合扫掠，统一步末影响 | 本轮用Context7核对实际API；不从后台直接读取主线程物理空间，不因射手死亡抹掉已发射物；没有引入第二物理时钟 |
| 多格目标选最近占格；攻击移动不拴死原始起点；共享攻击冷却 | 顾问部分攻击距离/容量P0依赖未提供模块或自相矛盾，逐条对照而非全盘接受 |
| 原子交换先验双方最终容量；协作保存原自主状态；邀请取消保护后来指令 | 不把承诺视为完成，不把临时受邀者永久变苦力；方法、能力与可消耗灵气分别存在 |
| 读取候选只重建感知缓存，静态记忆离场冻结、重返刷新；底图与实物外观分开 | 不用最新真相刷新保存的旧记忆，也不让实时家具底图绕过记忆显示；开发HUD仍可显示真实后台值 |
| 当前采用同一有限连通世界的真实旅行与持续推进 | 不采纳“必须永远分地图/Portal”的通用结论；也不把有限地区装配包装成已实现无限地图/远区LOD |
| 原领域显式状态列表+通用存读遍历 | 不为每个新增领域重写文件格式代码，不序列化任意Object；开发格式可替换，不延续旧档迁移链 |

最终跨域顾问提出的枯树修行完成校验是有效发现；预约等待、拆除清理、协作恢复的核查项在本地已有实现。我们另核查并修复了即时攻击/持续追击的双冷却，以及飞行输入与显示拾取偏移。真正的共同边界由小反例、独立新进程存读及同一release混合窗口确认；未测收益和闭源游戏内部class仍不写成事实。


## 格子视野与静态记忆修复

2026-11-12实际截图显示细碎暗射线；源码确认CPU稀疏探索与GPU逐像素遮挡不是同一判定。现统一为玩家局部格图，GPU仅滤波掩码，地表/静态对象保存最后所见，动态人物按当前可见格过滤。Godot官方[ImageTexture.update](https://docs.godotengine.org/en/4.7/classes/class_imagetexture.html#class-imagetexture-method-update)的同尺寸/格式纹理更新能力经Context7核对；采用R8值纹理与版本化脱离发布，不引入每NPC全图或新的并行调度器。

一次非流式顾问源码review提出地形版本变化、记忆索引边界和图像边界取舍，前两项已核实补足；顾问假定植物阶段不更新layout_revision，实际Nature._sync已有更新，不再加一套外观版本。其建议隐藏迷雾外HUD原数值与用户当前开发诊断需求冲突，未采用；普通世界显示仍遵守视野。部分看见的多格静态对象仍记住其整体外观，柔边是显示近似，不把它宣传为严格连续光学。另自主审查补上跨会话相同revision仍须更新纹理的epoch判断。实际成本和短窗只查BASELINE，原问答留本机fog-grid-20261112目录。

## 全单位感知与战斗视野咨询

2026-11-12用户在纯玩家遮罩实验期间提出战斗单位都需要视野属性。两份非流式顾问分别比较架构路线和查反例，均正常stop返回；原问答和逐项核查留本机`unit-sight-20261112`。讨论方案和未提交状态分别归唯一主计划、HANDOFF，本节不表示战斗接入已经实现。

实际源码确认：生活观察调用共同的距离加损耗判定；战斗发现仍用固定半径加物理硬阻挡，已有目标则用实时位置追路，受击也直接锁定攻击者。当前只有全局24视距，预准备格线的覆盖范围还与它耦合。这些是本次要收敛的真实缺口，不是另造一套世界结算内核。

公开证据：OpenRA的[AutoTarget](https://github.com/OpenRA/OpenRA/blob/playtest-20261026/OpenRA.Mods.Common/Traits/AutoTarget.cs)先查询附近候选并过滤可见性，扫描间隔分散；[RevealsShroud](https://github.com/OpenRA/OpenRA/blob/playtest-20261026/OpenRA.Mods.Common/Traits/RevealsShroud.cs)向玩家迷雾贡献视野；[AttackFollow](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Traits/Attack/AttackFollow.cs)维护最后可见目标，隐藏时可追旧位置；[FrozenUnderFog](https://github.com/OpenRA/OpenRA/blob/playtest-20261026/OpenRA.Mods.Common/Traits/Modifiers/FrozenUnderFog.cs)保留离场静态外观。[Mindustry FogControl](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/game/FogControl.java)按队伍维护当前/探索位集，[Units](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/entities/Units.java)用附近查询和可见性过滤目标；其中AI视野有特殊豁免，不能照搬为本游戏的共同规则。闭源War3/RimWorld的具体内部算法未据此声称已确认。

| 采用为方案方向 | 限定或未采用 |
|---|---|
| 每单位有视距，NPC按候选查询，玩家格图适配共同感知规则 | 不把所有单位有视野等同每人周期性生成整图；近处候选在密集交战也可能很多，不能固定假设只有个位数 |
| 新目标发现分散，攻击前复核，失去视野保留最后所见 | 和平NPC不能因为没有战斗订单就永远不看威胁；检查可见性可以读取真实位置，失败后不能把它泄漏给行为或记忆 |
| 感知衰减与物理阻挡分开，已发射物继续碰撞 | 顾问示例把受击时射手当前坐标当线索、或无条件初始化last_seen，仍会泄漏隐藏真相，拒绝；真实受击方向也不等于精确知道发射点 |
| 批量纯数据查询可复用CPU工作池，结果由owner提交 | 不把所有小查询强制派任务，不并发修改现有缓存；也不采纳将owner单线程或“禁GPU”升级为全局规则 |
| 同一格图负责探索/静态刷新，GPU仅柔化显示 | 二值shadowcasting不能原样替代当前距离损耗；带权传播可能绕墙改变含义。顾问对所有改进算法必然失败的断言没有证据 |
| 对比缓存、连续格线与预算早退 | 两答给出的70%/90%归因及亚毫秒目标均无实测，不能据此直接删除缓存或承诺速度；共享队伍图也不必然低效或导致个人知识全共享 |

Godot 4.7的[RenderingDevice](https://docs.godotengine.org/en/4.7/classes/class_renderingdevice.html)文档经Context7核对：`texture_get_data`同步阻塞，但也有`texture_get_data_async`。本场景需要CPU小批即时感知，暂无证据表明搬到GPU再回读有收益；这不是引擎没有异步回读，也不是以后大批宽容延迟任务不能用GPU。本次未实施新感知算法，既有迷雾候选性能证据仍只查BASELINE，不能当作全单位新视野的实测。


### 实施后的核查与取舍

用户随后授权完成，共同几何已独立为`sight.gd`，玩家记忆留`perception.gd`，`combat_scan.gd`负责脱离的索引/观察者CPU批，结果回owner提交。常用连续格线表与预算早退替代共享写格对缓存，长半径走同公式后备；这同时避免worker写缓存和固定24格上限。普通静态物视距默认0，查询不要求移动页；当前主动警戒/战斗调度仍面向已有移动人物，未借本轮预建炮塔、队伍共享或完整注意力平台。

又做两次high思考源码咨询，实际请求固定携带用户指定的`thinking: high`；均完整stop返回。采用的反例包括：守卫不能永久锁射不到的目标，失联搜索要按实际寻路终点结束，不可达接触不能每隔短冷却就打断长工作，以及反击应保留原攻击方式/实际来向。对应的观察、失败位置记忆、复核和时间透传在原owner中补足，没有另造行动系统。古树阶段通知经核查已有，不加重复版本；同步损耗当前没有可测热点，不扩成跨域dirty日志。顾问的静态“已验证”不代替本机短反例和容量窗口。

单步准备、批计算/join、采用和显示分别计量；实际性能及未测范围只查BASELINE。单次视线无需强制派任务，团队格图也未被禁止；当前做法是此负载的选择，不是未来不可改的架构信条。原咨询、失败/未采用实验及逐项取舍保存在本机review，不把过程副本继续铺到AGENTS或唯一主计划。


## 临时像素美术的清单与源码核查

2026-11-12按用户指定服务，两次非流式Argon-search咨询均带`thinking: high`、131072输出预算并完整stop返回：先比较全世界清单与来源，再审查实际批绘/显示代码。另4次图像请求生成角色八向底姿、地物、生物、植物阶段；实际使用模型为`gemini-nano-banana-2.1`。本机原请求/回答与逐项记录留`.local/advisor/runs/temp-art-20261112-*`，不入库。

采用混合方案：Kenney三包CC0的精选物品、生成后规整的统一角色/地物/植物、程序绘制的规则墙门/地面/派生动作/特效。许可与完整清单只归[assets](../../assets/README.md)。现成免费包若不允许公开原图再分发则不使用；Google输出不是项目另行声明的CC0。

源码核实后修正了多格家具`Rect2i.expand(point)`漏掉末格（改merge单格矩形）、蓝图尺寸、屋顶排序/遮雨、飞行受击高度与头顶裁切、同epoch/身份受击残留、搬运停步、攻击显示被插值位移覆盖、天气遮住迷雾/夜间反向增亮、暂停同时间戳的天气刷新。采用Shader内有界影子/图集动画、Godot CanvasModulate、单屏天气和原有迷雾；没有每人灯光、粒子节点或权威GPU回读。

拒绝或限定：第一答给错S起始方向、漏看独立fog层，不据此改真实N起始方向或叠第二次暗化。第二答的“单位身份缓存必定过期”未成立：当前spawn/remove先经Objects.create/remove_empty，已提升layout_revision；不另加逐步全量拷贝。动物仅静态预备，并未共用人形死亡行，不采纳其“必定串成人尸”推断。未直接采用所有资源许可断言、P0等级或GPU耗时承诺；方向/Alpha/脚点/状态/昼夜等经过实际图像与短反例核查，性能以BASELINE的同负载release窗口为准。完整装备解剖挂点、全动物动画仍为临时包边界；人物/地物跨批排序由下一节的截图反馈修复。

## 地块分层、完整精灵和柔和视野

2026-11-13核对用户截图后，两次Argon-search长问分别审视生境/施工和素材/视野，均带`thinking: high`、131072预算、非流式并正常stop返回。原问答及逐项取舍留本机`tile-environment-20261112`目录。顾问是找反例与路线的工具，不把其性能数字、铁律或闭源游戏内部实现当事实。

可核实的成熟参考：[Mindustry Tile](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/world/Tile.java)把自然floor、overlay和block/build分开；[Godot TileSets](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html)提供可独立于地图格尺寸的图块区域、原点与terrain邻接；[OpenRA官方trait说明](https://docs.openra.net/en/release/traits/#shroudrenderer)列出角/边bitfield、独立fog/shroud图帧和混合方式。后者支持“逻辑网格不必原样显示成方格边”的取舍，不等于已读到其当前渲染源码，也不能据此声称War3/星际使用了本项目公式。

| 采用并在源码核实 | 未采用或限定 |
|---|---|
| 基底/地被/地板与实体分开，自然撒布统一检查生境、地板和房间 | 不把室内禁自然生成扩大为清除玩家后来围起的植物，或禁止地板上的花盆 |
| 低草在地板完工时清除，树/桩先清；库存和多格来源身份保留 | 压力木料点仍是有限库存fixture，不伪造完整生长/砍伐经济；清场不复制库存 |
| 校正实际不等高行切片、量化后的透明边和每类锚点，整树跨格显示 | 图集单格大小不等于世界占地大小，不把树拆成分别参加前后排序的散片 |
| 人物与静态物合并原批绘，按脚点排序；静态物依据根部整体显示记忆明暗 | 顾问提出的树冠/树干双pass不自动解决所有墙/家具/人物排序，“零开销”或固定耗时承诺没有测量依据 |
| 预平滑环境损耗、连续视野余量、显示羽化与冻结记忆分工 | 没采用另一套仅玩家径向波前/噪声判定，也没给每NPC生成整图；当前查询规模没有证明额外算法必要 |
| 既有邻接方向选图支持墙角/分叉，两朝向门与地板在格脚对齐 | 没为已有数据批绘再维护一份实时TileMap世界；Godot原生Terrain仍可用于适合的静态关卡，不变成禁用规则 |

实际视觉反例确认整树、墙转角/拆后更新、前后人物和离场整树缓存；短反例和同最终包的吞吐证据只登记BASELINE。仍允许近似感知/姿态排序，不将这一轮修复写成强制未来全部系统采用的全局范式。

### 第二轮截图：方向、裁边和地面接触

用户仍看到逆行雨、树冠平直裁边、分离影子和窄墙露地板。独立Argon-search审阅（thinking:high、131072预算、488秒、正常stop）与实际图像核查确认这些是不同原因：天气采样的`+vt`令可见图案反向；QuadMesh与Control不能共用随意翻转UV；world源图的树冠跨过名义列边界；窄墙只覆盖真实阻挡格的一条带；压缩轮廓影使细树干采样断裂。上一轮静态远景没有覆盖这些反例，不能继续宣称裁边与悬浮已全部排除。

采用原始局部顶点构造素材像素、天气反向采样位移、按实际留白分列、占地中心接地、整格墙和有界接触影。家具改为程序原创轴对齐顶视四向，多格旋转同步原对象的占地/外观/存读；没有把生成的斜透视图旋转90度当新方向。原始素材保留追溯，未新增外部包。[Godot CanvasItem shader文档](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html)及变换接口经Context7核对；Kenney和LPC Wooden Furniture检索只供选型，具体来源归assets。

没有照搬顾问的放大窗口伪“连通域切分”（仍可能取错邻居）、含内缩边的伪整格墙、“零成本/固定指令数”承诺或对所有LPC合图的笼统许可判断。其基于文本称plants为1024宽，实际PNG也是1536宽；视觉源图优先。其max风摆示例在四顶点quad插值下仍会挪动根部，实际改为绕根线性切变。雨/飘絮的双时刻真实GPU截图、八向运动/四向床、近景接地与同包负载的证据只归BASELINE；不把原咨询再复制成约束。

### 任意角度移动：方案核查，尚未实现

2026-11-13用户反馈只能横竖行走，要求类似RTS的任意角度移动，并与顾问讨论方案。方格用于地形/建筑不等于单位只能四向或八向；八向素材也只量化显示朝向。当前限制来自三个真实环节：`terrain.navigation()`显式禁用斜向并用Manhattan距离；鼠标命令先丢弃小数落点；`Units.advance()`虽然持有连续位置，却逐个走整数路线的格心。仅改diagonal_mode、把get_id_path换成get_point_path，或在显示端画曲线均不满足要求。

本次向本机Argon-search提交约14.8万字符的产品背景和实际代码，thinking:high、非流式、98304输出预算。首请求因账号验证失败，用户恢复服务后重试已完整返回：412秒、约2.56万字符、finish_reason=stop；原错误、成功问答及独立核对留忽略的`free-angle-movement-20261113`咨询和`free-angle-movement-20261113-retry1`运行目录。顾问支持连续坐标/通路分离，但多处细节需纠正，取舍见下文；实施顺序只维护[主计划](../../docs/plans/foundation-priorities.md#待实施方案任意角度移动与共同导航)。

| 来源 | 能确认的经验 | 对本项目的意义 |
|---|---|---|
| [Red Blob格网优化](https://www.redblobgames.com/pathfinding/grids/algorithms.html)、[Theta*原作者论文入口](https://idm-lab.org/bib/abstracts/Koen10r.html) | 格网可用于搜索，输出路径不必沿格边；事后拉直不保证欧氏全局最短，Theta*也不能笼统等同最优路径 | 任意角行走可先用原生通路搜索配几何合法的直线段；是否需换搜索算法由路径品质/成本反例判断 |
| [0 A.D.当前可读接口](https://github.com/0ad/0ad/blob/master/source/simulation2/components/ICmpPathfinder.h)、[2012年设计解释](https://www.indiedb.com/games/0-ad/news/the-pathfinding-saga-continues) | 长距离格图、短距离精确路径、点/圆/方形目标、异步请求身份与移动检查分开 | 采用职责分离，不把旧文中的导航格细分数量变成我们的参数，也不宣称Warcraft/StarCraft闭源内部相同 |
| [GridStringPulling文档](https://arongranberg.com/astar/documentation/stable/gridstringpulling.html) | 成熟库支持格图路径拉直，和navmesh funnel概念相似而算法不同 | 可借鉴公开原理，不引入Unity依赖，也不把任意删节点或Bezier曲线冒充合法路径 |
| Godot [AStarGrid2D](https://docs.godotengine.org/en/4.7/classes/class_astargrid2d.html)、[线程安全](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html) | 原生格图支持无切角斜向，单张AStarGrid不能并发搜索；NavigationServer2D支持并行查询 | 格图候选保留lane私有上下文；NavServer候选也可不建每人节点，不因多核现状否决原生导航 |
| Godot [导航性能](https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_optimizing_performance.html)、[烘焙](https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_using_navigationmeshes.html)、[地图同步](https://docs.godotengine.org/en/4.7/classes/class_navigationserver2d.html) | 网格复杂度取决于多边形/边数，不可达搜索可能很贵；纯数组几何能后台烘焙，地图更新默认在物理帧同步，force_update涉及服务器锁及队列刷新 | 原生navmesh是有竞争力的候选，不能凭直觉说一定慢；但动态墙、不同半径和自主模拟时钟仍需显式衔接，不能把每格navmesh或每步force_update当捷径 |

当前首选是原生AStarGrid提供通路、带身体净空的直线段路线与连续跟随，先用原生NavServer小原型反证其适用性。首选依据是现有可建造格地形、增量阻挡与lane执行边界契合，不是必须保留旧类。若大体型/窄道需不断细分格网或叠补丁才能满足，或同负载品质/端到端成本明显不如NavServer，直接换导航表示；不强制走完格网改造再承认失败。Theta*/Polyanya、自建可见图和flow field保留为有具体证据时的专项候选，不同时建立多套生产后端。

实现不可漏掉的边界：连续起点/终点及同格不同落点、非格心改令、按身体半径检查整条线段、局部不可达终点的明确反馈、追击最后所见及作业操作位、路线缓存不串角色端点、动态新墙命中长线段中部、存读与身份/命令版本。现有大体型整数净空图比实际0.9格半径保守，可能拒绝几何上能通过的两格宽通路，不能原样当精确解。基础步跨拐点时显示插值与弹道的起末直线近似也须核对，不能只看一张截图说移动成立。

性能方面先走可达直线快路、按事件求路/失效、缓存共享通路而端点单独连接，保留CPU池和批量绘制。平滑需有界的几何检查，不用所有路点两两试探；请求数量预算也不能限制单次不可达原生搜索的最坏耗时，需单独测量。低优先级NPC求路可分批等待，已在有效路线上者继续移动；不能丢命令或让陈旧异步结果覆盖新指令。GPU继续显示插值，不为稀疏寻路强行增加回读。完整避让/推挤/编队不作为本轮任意角移动的前置条件。

顾问复核后的采用与纠正：

- 采用连续目的地/连续路点、共享格通路与私有端点、按半径检查线段和建墙占用、按需路径预览。源码确认`Facilities.finish`及调试建墙入口只按圆心所属格检查占用，新墙可能碰到邻格身体；应和移动净空共用几何语义。大体型交互的格心距离和操作位也需一并核对，不能只改右键。
- 拒绝其“大体型3×3整数扩张拓扑完全正确”的断言：两格宽通路对半径0.9的身体仍有宽0.2的圆心区间，但整格心采样/扩张会封掉；此反例保留在首个原型，不能以顾问赞成为由删除。
- [Rect2公开方法](https://docs.godotengine.org/en/4.7/classes/class_rect2.html)没有顾问反复引用的GDScript `intersects_segment`。线段/膨胀矩形的算法仍可用，但需选实际可调用的几何原语或小型区间裁剪，不复制无效API，也不引出第二套物理引擎。
- 不接受其“前向窗口保证全部几何工作O(L)”：每个锚点先测遥远终点，单次长线又可能遍历大量格子；格路线后方可见性也不单调。需量总访问格数/候选数，不能只计LOS调用次数。局部钳制也不保证迭代两次就合法，零距离/无解须明确返回而非输出穿墙点。
- 不接受其“每次改墙全图重建两套连通分量能零成本拒绝不可达”。标签查询便宜不代表维护便宜；连通性预判按突发测量决定，变化后的陈旧标签不能直接作否定结论。不照抄24次搜索、24格平滑窗口、2.5ms切换阈值或无依据的20–40倍脚本差值。
- 保留跨拐点轨迹/显示/弹道核查，拒绝“误差小于身体半径，所以绝不会视觉穿墙或改变擦边命中”。半径是几何尺寸，不是额外安全余量；一条总长0.25格、绕角切线净空0.351的合法折线，其端点弦线距角可仅0.33066，小于身体半径0.35。这个数学反例不是当前游戏实测；需按最终选用的净空与轨迹验证，或明确保留经过验证的有界近似。
- 保留原生NavServer对照。官方[线程安全文档](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)明确查询可以真正并行，更新同步的整合成本不等于架构不兼容；4.7的`map_force_update`还已标为不支持异步更新的弃用方法，不能把每步强制同步当方案。拒绝顾问的“最佳/零成本/100%命中率”承诺与禁止一切原生节点的绝对规则，最终取舍仍据几何反例及端到端测量。
