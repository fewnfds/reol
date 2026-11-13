# 方格世界中的位置、占地与移动

> 研究资料：记录来源与适用限制，不授予引入依赖或改变规则的权限。

核读日期：2026-11-05。本页回应用户撤回“全对象格位置权威、移动动画纯视觉”的临时结论；是竞品研究及技术建议，不是新的实施授权。方格地形、一实体一份状态和可多格占地仍沿[既定规则](../rules/objects-and-interaction.md)；当时的坐标候选保留供比较。

当前连续移动与采样精度分别见[架构](../../docs/engineering/architecture.md#连续移动与共同导航)和[运行与精度](../../docs/engineering/simulation-pacing.md)；以下建议不代表待执行任务。

## 研究结论

成熟项目存在不同组合，没有“方格地图必然要求人物整格移动/停格心”的共同规则。**单位的逻辑位置可以细于地形格，而且参与真实玩法；画面还可以另做插值。** 反过来，整格生物模型也能支撑复杂世界，但有其玩法取舍。

必须分别讨论以下职责，不能由其中一个推出其余所有答案：

| 职责 | 要回答的问题 |
|---|---|
| 地形与区域 | 土地、墙、屋顶、房间和用途区域如何索引 |
| 放置占地 | 床、柜、岩石等一实体覆盖哪些格，是否排他 |
| 单位逻辑位置 | 行走中和停止时的位置精度，哪些系统读取它 |
| 碰撞与通行 | 身体实际阻挡范围、狭道净空、途中扫掠和动态占用 |
| 导航 | 用什么网格或区域规划路线，如何交给运动器执行 |
| 环境采样 | 来源位置、受影响格与距离采用多大精度 |
| 呈现与选取 | 如何插值、绘制与点击，不另造权威事实 |

## 有直接证据的项目

### Factorio：方格建造与子格逻辑位置并存

官方API文档读取版本为 **2.1.24**，不是据贴图推断：

- [MapPosition](https://lua-api.factorio.com/latest/concepts/MapPosition.html)说明内部坐标以32位整数保存，8位为小数，精度为1/256地块；Lua接口的double不代表内部一定用浮点。
- [EntityPrototype](https://lua-api.factorio.com/latest/prototypes/EntityPrototype.html)分别定义碰撞框、选取框与建筑尺寸。`tile_width`为奇数时建筑中心对齐格心，为偶数时对齐格边界；有off-grid例外。
- [ItemEntityPrototype](https://lua-api.factorio.com/latest/prototypes/ItemEntityPrototype.html)给出的地面物品示例也允许off-grid，碰撞框与选取框不同。掉落物不天然必须在整格中心。
- [FFF-317](https://factorio.com/blog/post/fff-317)（2019-10-18）描述分层寻路：地图按32×32格分块，寻路器可多tick返回waypoints。格子/区块是规划和索引工具，不等于只在格心保存单位。

适用边界：API和旧开发日志只支持上述结构结论，不提供Reol的帧耗承诺。`latest`会变化，复核时须同时记录页面版本。

### OpenRA：格路线、占用状态和格间玩法位置并存

核对正式版 **release-20250330**，源码提交 `b4f3d8ae02b6bd6f4a3a5441e6d0daf7c5073787`：

- [Mobile](https://github.com/OpenRA/OpenRA/blob/b4f3d8ae02b6bd6f4a3a5441e6d0daf7c5073787/OpenRA.Mods.Common/Traits/Mobile.cs#L238-L263)同时维护同步的`FromCell`、`ToCell`、`CenterPosition`。`OccupiedCells()`另区分子格共享及移动占用。
- [Move](https://github.com/OpenRA/OpenRA/blob/b4f3d8ae02b6bd6f4a3a5441e6d0daf7c5073787/OpenRA.Mods.Common/Activities/Move/Move.cs#L460-L500)在逻辑推进中按速度更新进度，以`WPos.Lerp`计算位置，再写入`SetCenterPosition`。
- [AttackFollow](https://github.com/OpenRA/OpenRA/blob/b4f3d8ae02b6bd6f4a3a5441e6d0daf7c5073787/OpenRA.Mods.Common/Traits/Attack/AttackFollow.cs#L94-L100)直接用`self.CenterPosition`判断射程。因此格间位置具有玩法意义，不能统称为纯视觉动画。
- [Building](https://github.com/OpenRA/OpenRA/blob/b4f3d8ae02b6bd6f4a3a5441e6d0daf7c5073787/OpenRA.Mods.Common/Traits/Buildings/Building.cs#L34-L39)以多格footprint描述建筑，各格可有不同阻挡性质。

适用边界：这是有格路线约束的RTS实例，不能由此声称它具备任意自由动作或Reol应复制整套系统。定点/整数子格也是子格，不必把选项简化为“整格或浮点”。

### Dwarf Fortress：允许视觉大于生物逻辑定位

[官方开发日志](https://www.bay12games.com/dwarves/) **2020-04-08** 说明：当时巨龙可在画面覆盖约3×2格，游戏逻辑仍把生物放在一格，有时同格有多个生物。该页另有多生物、建筑和物品同格时的选取说明。

这证明整格生物及多对象共格是其明确采用过的取舍，不能单凭2020年的说明断言所有现版细节不变。它适合研究聚落模拟的简化；不能自动保证自由瞄准、精细碰撞或巨兽狭道观感。

建筑也不必随生物统一成一格。[DFHack stable API](https://docs.dfhack.org/en/stable/docs/dev/Lua%20API.html)（读取为53.16-r3）有建筑width/height、可选extents及`containsTile`等接口。DFHack是第三方工具证据，不能冒充游戏官方源码。

### Cataclysm: DDA：整格位置仍需额外体型规则

源码固定在 `c19bb0c1e1feb7b76877c74786f195813a6992cc`：

- [Creature::move_to](https://github.com/CleverRaven/Cataclysm-DDA/blob/c19bb0c1e1feb7b76877c74786f195813a6992cc/src/creature.cpp#L309-L324)接收并保存地图格坐标`tripoint_abs_ms`。
- [monster通行检查](https://github.com/CleverRaven/Cataclysm-DDA/blob/c19bb0c1e1feb7b76877c74786f195813a6992cc/src/monmove.cpp#L239-L242)拒绝较大生物进入`SMALL_PASSAGE`。

因此“一格定位”也不等于所有体型能穿同样的门；狭道错误不会仅靠统一位置单位消失。它是回合制作品，节奏和动作碰撞不直接适用于Reol。

### 0 A.D.：历史源码明确分开模拟与绘制插值

GitHub镜像已于 **2024-09-09** 归档；本次固定最后镜像提交 `61a3b9507d974084e6badb88a0826bd89a6d5b8b`，仅作历史架构证据：

- [CCmpPosition逻辑位置](https://github.com/0ad/0ad/blob/61a3b9507d974084e6badb88a0826bd89a6d5b8b/source/simulation2/components/CCmpPosition.cpp#L513-L520)的`GetPosition2D()`返回定点坐标。
- 同文件的[插值接口](https://github.com/0ad/0ad/blob/61a3b9507d974084e6badb88a0826bd89a6d5b8b/source/simulation2/components/CCmpPosition.cpp#L656-L670)另为绘制计算插值位置和变换。

这支持“逻辑位置已细于整格，画面再插值”的组合。旧Pathfinder Design混有已实现与待实现内容，不将其当成现版全部行为或性能证据。

### RimWorld：本次证据不足的部分

本次未取得足以核定最新版本全套移动、占用和碰撞实现的开发者一手材料。旧社区模组使用`Position`和`DrawPos`只能作线索，不据此填出内部算法；也不把第三方反编译仓库称为官方开源。

## 对Reol的建议，尚未拍板

结合方格建造、大世界模拟及既有动作战斗方向，建议优先评估以下组合：

1. 地形、结构和区域继续按格组织；家具和建筑部件可多格，一实体一份状态。
2. 人物及移动身体暂保留原权威子格位置，行走和战斗均读它；是否改定点、停止吸附及通行规格分别讨论，不因这轮研究先重写。
3. 导航可以使用网格/区块，输出路线给运动器；通行体型与碰撞另行校验，巨兽开路属于能力，不用穿墙掩盖无路。
4. 环境缓存可仍按格存值。移动来源可比较“从权威位置取所在格发源”与“按子格距离采样”；前者不会要求身体也格化，后者不会要求逐毫秒全图重算。
5. 呈现只插值已接受状态；真实模拟位置与格索引仍可同时存在，但只有一个位置所有者，派生索引不能变成第二份真值。

这是减少不必要迁入的建议，不宣告现有运动器或环境调度已经验收。当前`SimLocalMotion.position`和`SimRouteTravel.project`的连续位置参与规则；A1只读地面来源，未接携物移动场。

## 性能与选型出口

来源坐标精度、模拟tick、环境采样和绘制FPS是不同旋钮。用整数也可以细于格，用浮点也不意味着必须给每格创建物理节点。成本应测活动身体数、局部碰撞候选、跨格/采样事件数、影响半径、受影响缓存块及失效频率，不能仅凭坐标类型估算。

后续若排定空间/动态场包，先用同样输入比较直线、斜走、窄门、拐角、途中过半取消、慢走/快跑携源和在途重启；同时量测密集静物及活动来源负载。整格场近似须报告格边界跳变与沿途误差，子格场近似须报告切片误差与更新成本。此为选型依据，不新增当前自动执行队列。

本轮只撤回文档结论并调查，没有更换引擎、复制竞品代码或引入依赖。占地与巨型通行的补充研究见[体型与净空](unit_footprint_and_clearance.md)。
