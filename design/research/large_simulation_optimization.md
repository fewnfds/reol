# 大型模拟运行框架：一手研究与本轮裁决

研究更新：2026-11-12。这里记录可核查来源、适用边界与顾问取舍；不是第二计划。当前接口、能力与实测分别只查[架构](../../docs/engineering/architecture.md)、[FEATURES](../../docs/status/features.md)、[BASELINE](../../docs/status/baseline.md)。旧实现由Git的a493bf0追溯。

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
