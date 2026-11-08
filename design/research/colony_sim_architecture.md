# 类RimWorld模拟游戏：基础架构对照

核查：2026-11-07。Reol代码基于`b3ae3399d24e01975d231cd000c0af342740070b`只读核对；外部资料为公开Mod教程、作者视频说明/章节和Project Porcupine源码。本文记录来源与推论，不代表商业游戏内部源码审计、教学项目的生产成熟度或Reol实现验收。领域职责见[顶层框架](../../docs/engineering/architecture/05-framework-domains.md)，建设依赖和出口只在[基础建设计划](../../docs/plans/foundation-priorities.md)维护。

## 可核实的参考

| 来源 | 核查到的结构 | 证据限度 |
|---|---|---|
| RimWorld社区Mod教程：[ThingDef](https://rimworldwiki.com/wiki/Modding_Tutorials/ThingDef)、[ThingComp](https://rimworldwiki.com/wiki/Modding_Tutorials/ThingComp) | 定义与实例分开；人物、植物、装备、建筑可以通过ThingWithComps组合能力；提供初始化、进入地图、离开地图、销毁、存读和不同tick入口 | 社区教程，部分hook说明标注旧版本；可证明公开接口模式，不能保证当前所有签名或推出其使用完整ECS |
| RimWorld社区教程：[Example Mending Job](https://rimworldwiki.com/wiki/Modding_Tutorials/Code_MendingJob) | JobDef选择JobDriver，后者组织Toils；示例贯穿目标预约、接近、执行、失败条件和清理，玩家操作也提交Job | 是具体Mod执行链，不证明所有过程都能任意数据编排；不能把Reol所有控制通道压成一个动作 |
| RimWorld社区机制页：[Rooms](https://rimworldwiki.com/wiki/Rooms)、[Temperature](https://rimworldwiki.com/wiki/Temperature) | 围合、屋顶、用途与温度条件分别成立；房温按房间聚合，室外有共享背景简化 | 玩法机制证据；页面阈值表述存在差异，本研究不采用其数值，也不据此推断内部算法。Reol室外局部冷热不适用这一完整简化 |
| 《了不起的修仙模拟器》：[官方介绍](https://store.steampowered.com/app/955900/Amazing_Cultivation_Simulator/)、[iguana Mod指南](https://github.com/iguanacore/acs-modding-guide-iguana) | 官方描述材料特性继承及五行/风水布置；社区指南展示Settings定义、ThingDefs与Scripts/Lua分工、定义加载和覆盖 | 官方功能介绍不证明内部代码；社区指南含旧版本信息。其指向的官方`api.gsqstudio.com`本次不可访问，未核实调度器、空间索引或Job内部实现 |
| quill18 / Project Porcupine：[项目声明](https://github.com/TeamPorcupine/ProjectPorcupine)、[World.cs](https://github.com/TeamPorcupine/ProjectPorcupine/blob/master/Assets/Scripts/Models/Area/World.cs)、[RoomManager.cs](https://github.com/TeamPorcupine/ProjectPorcupine/blob/master/Assets/Scripts/Models/Area/RoomManager.cs) | World组合地块、人物/家具/库存管理、JobQueue、房间和路径图；空间变化有通知，路径图可失效；房间管理有分割/合并事件 | 已实际打开两份源码；是Unity教学衍生项目，源码含TODO及全局访问，不能当成已交付商业引擎 |
| Real Robots：[Terrain Generation](https://www.youtube.com/watch?v=7CuoC_pB9-k)、[Pathfinding & Pawns](https://www.youtube.com/watch?v=PIPlWCyHf7s)、[Pawn AI - Task System](https://www.youtube.com/watch?v=p6utAZMkZeg) | 作者说明和章节展示地形、移动成本、单位，再用任务/子任务组织寻找、走近、拾取、进食 | 核对视频页面说明和章节，未逐帧观看整套课程或运行下载工程；说明教学顺序和复用思路，不证明存读、远区或大规模性能 |

Project Porcupine社区代码默认GPLv3，非代码资产默认CC BY-NC-SA；原作者另行提供的无社区贡献教程工程声明MIT。本研究仅分析接口和组织，不复制代码/资产或引入Unity、C#、Lua运行依赖。RimWorld与修仙模拟器的公开Mod能力也不构成可直接移植的通用引擎。

## 从参考中得到的架构判断

以下是对Reol的工程推论，不声称几款游戏采用完全相同的实现。

1. **领域分工与公共运行合同是两个维度。** 建筑、植物、环境、行动各有职责；定义/实例、空间归属、生命周期、时间和存读应使它们能够组合。七个领域可以保留，新增内容接入合同比重排目录更有价值。
2. **能力组合不等于万能对象或完整ECS。** 同类机制可由定义复用，新的机制仍由代码实现。共同引用、能力查询和生命周期通知可以适配不同原owner，不要求把所有状态搬进同一Dictionary或给每株草分配Node。
3. **地图包含多种事实。** 地表、对象占地、屋面、区域指定和派生围合分别维护；空间查询组合它们。容器中的对象仍存在，离开地图与销毁应有不同语义；查询索引只持可重建投影。
4. **行动基础从早期就参与建设。** 建造、采集等过程需要接近、预约、耗时、复核和清理。先以已有取放/施工形成可复用合同，再让新领域接入；完整运动、特殊穿行和复杂策略可继续扩展。
5. **环境按游戏语义选择模型。** 可借鉴房间聚合和拓扑通知，同时保留Reol已确认的室外局部来源、残留及五行语义。成熟作品的简化不是必须照搬的约束；风水利用真实布局/材料/环境，具体规则由本项目决定。

## Reol现有代码对照

下表只表示受检版本的边界，不把有限样本直接判成错误实现。当前可用范围仍以[技术总表](../../docs/status/technical-status.md)为准。

| 位置 | 实际核对 | 架构含义 |
|---|---|---|
| [ReolContentDB](../../scripts/data/content_db.gd)、[ReolContentBundle](../../scripts/data/content_bundle.gd) | 已有定义加载、内容绑定及digest，定义与运行事实分开 | 继续扩展现有内容路径；新增已有能力的内容应尽量无需更改机制分支 |
| [SimWorldObjectQuery.capture](../../scripts/sim/world_object_query.gd) | 明确只捕获调用者提供的引用，结果是历史快照；地面与结构另有局部索引 | 补各原域的局部候选和变化接缝，组合成有界实时查询；无需重建一个持有全部状态的对象库 |
| [SimObjectLifecycle](../../scripts/sim/object_lifecycle.gd)、[SimGroundPlacements](../../scripts/sim/ground_placements.gd) | 受管physical器物、同账本材料已有事务；committed通知及revision只覆盖相应地面域 | 向建筑/植物扩展时明确原owner的初始化、空间进入/离开、终止和恢复接缝，不误用局部revision代表全世界 |
| [SimConstruction.valid_definitions / register_site](../../scripts/sim/construction.gd) | 校验器固定四种wood类型；已有工地时拒绝新登记，项目绑定sect_yard；原材料与施工阶段真实存在 | 主要扩展点是结构定义、工地/实例和几何的一般化；保留原库存、材料与工时，不用另造演示施工器 |
| [SimActionExecutor](../../scripts/sim/action_executor.gd)、[object_actions.gd](../../scripts/sim/object_actions.gd)、[SimConstruction](../../scripts/sim/construction.gd) | 生活动作、耗时取放和施工分别维护过程；已有travel、预约、截止、中断等基础，但并非覆盖全部域的共同协议 | 提炼可复用的过程接缝和结果语义；领域继续提交各自效果，不必换成一个包办所有业务的执行器 |
| [SimLandResources](../../scripts/sim/land_resources.gd)、[SimWorldObjectQuery](../../scripts/sim/world_object_query.gd) | 自然资源保留原库存和生长/采出账；查询明确标记independent_plant=false | 完整植物实例是实质缺口，应接入共同空间/环境/行动；不能只加树木画面或再复制一份产量 |
| [RegionalSimulation](../../scripts/sim/regional_simulation.gd)、[WorldRestoreFactory](../../scripts/sim/world_restore_factory.gd) | 已有共同整数毫秒、明确有序阶段、欠算与独立候选恢复；初始化/恢复仍显式装配领域 | 保留确定次序与失败原子性；随真实新领域补接装配，不按脚本长度或教程风格全面改造调度器 |

现有纯sim与runtime/UI分离、原状态唯一、共同时间及候选恢复方向合理。没有外部证据要求换引擎、把连续身体位置改成整格，或强行合并器物/数量/植物的原状态；位置精度继续沿[空间研究](spatial_models.md)和[当前架构](../../docs/engineering/architecture/03-time-space-presentation.md)单独评估。

## 可直接查看的教程

| 系列 | 链接与适合查看的内容 | 使用方式 |
|---|---|---|
| quill18creates — Unity Base-Building Game Tutorial | [完整播放列表](https://www.youtube.com/playlist?list=PLbghT7MmckI4_VM5q3va043FgAwRim6yX)、[已核实的Episode 2页面](https://www.youtube.com/watch?v=hnC8iSehFSM)、[Project Porcupine仓库](https://github.com/TeamPorcupine/ProjectPorcupine) | 学习地块世界、模型/显示分工和系统逐步组合；2015年开始的Unity课程与后续社区仓库分别判断，不直接照搬API或所有实现 |
| Real Robots — How to make Rimworld in Godot 4 | [完整播放列表](https://www.youtube.com/playlist?list=PLOb5IPYDOceDIeNvojEYIUeHbHTZShtc-)；上表三集页面已核实，2024年发布 | 与现有Godot技术栈更近，重点看地形→单位→物品→任务组合；本次读取不到播放列表完整正文，以单集页面为证据 |

对后续修改的建议是：保留领域划分，将最小行动合同纳入基础承载建设；让建筑和植被通过实际操作检验对象、空间、环境与存读接缝；环境和行动继续随领域加深。准确交付目标、顺序及验收统一回到[基础建设计划](../../docs/plans/foundation-priorities.md)，本页不另设执行队列。


## 建筑与家具的补充对照

[RimWorld社区ThingDef文档](https://rimworldwiki.com/wiki/Modding_Tutorials/ThingDef)与[ThingComp文档](https://rimworldwiki.com/wiki/Modding_Tutorials/ThingComp)支持定义/实例/附加能力分工；人物、植物、装备、建筑可以共享基础合同，各自保留专属状态。这是公开Mod接口的结构证据，不是商业引擎内部源码审计。

[Project Porcupine的Furniture源码](https://github.com/TeamPorcupine/ProjectPorcupine/blob/master/Assets/Scripts/Models/Buildable/Furniture.cs)把墙、门、沙发等已安装对象放在共同可建造模型中，具有多格尺寸、朝向、能力组件和HealthSystem。[Cataclysm:DDA的家具数据文档](https://github.com/CleverRaven/Cataclysm-DDA/blob/master/doc/JSON/JSON_INFO.md)分别表达储液、工作台、照明、收起、破坏等条件；它的terrain/furniture和creatures不是同一个对象模型，说明共同接口不要求全部继承人物。

对Reol的采用是共同引用、原owner及按需能力：墙和家具可受击，主动攻击另由实际攻击能力实现；操作位和设施关系支持桌椅/工作台，容器引用原库存。围合、覆盖、通行、视线、环境阻隔分别提供事实。房间和用途不自动生产物品或授予知识，静态家具没有无用的人物AI或持续更新。这里只分析结构，不复制GPL源码或第三方资产；具体工程行为见[建筑合同](../../docs/engineering/construction-contract.md)。
