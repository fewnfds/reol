# 当前接续

更新：2026-11-11。最新用户要求完成整个多核计划并测出复杂世界上限。共享几何之后已落地**身体显示发布的任务池消费者、同输入CPU场计算、真实线程CPU采样及可扩展复杂场景**；主要模拟协调线程尚未迁移，任务继续。当前分支/提交以Git为准。

当前阶段及交付顺序只看[主计划](../plans/foundation-priorities.md#当前阶段主要模拟负载多核化)，目标线程/数据/依赖结构看[执行方案](../specs/world-engine/execution.md)。下一小阶段是**独立模拟协调与主线程的安全交接**，继续扩大主要负载并行。身体显示已脱离活对象，其他面板/画布仍依赖完整边界的原世界读取；不能直接把runtime Node搬到后台。

## 接手入口

- [计算范式](../engineering/settlement-contract.md#计算优化范式)是新增领域选择事件、周期、变脏、延后、续算及CPU/GPU路径的唯一正文；具体频率与宿主预算见[运行合同](../engineering/simulation-pacing.md)。
- [代码入口](../../scripts/README.md)、[owner表](../engineering/architecture/02-owners.md)定位原状态；[唯一计划](../plans/foundation-priorities.md)保留范围与暂停候选。
- [BASELINE](baseline.md)维护当前版本、测量及验证限制；旧性能实验在[历史记录](../archive/qa/20261111_performance_experiments.md)，不自动续做。

## 当前事实

`SimWorldGeometry`由RegionalSimulation持有，16×16格页复用、局部变更替换页，捕获的旧页保留只读且带来源/版本。普通人物/服务已直接绑定模拟层导航与依赖失效，不再借runtime Node；共享AStar同步入口保留，worker只能用私有`Search.find_path`。原地图/建筑/植物/大身体仍持有原事实，不增加存档格式。

`SimBodyReadView`每交锋边界由owner捕获一次紧凑列；`SimSpatialQueries`用原Godot任务池批量查线段候选，原交锋按固定顺序采用。当前仍同步收集，不具备跨帧交锋游标。300人45秒混合release为0.992210×、P99 18.704ms，无世界错误；同刻飞行物少，空间并行批为0。纯候选300×64探针约1.95ms→4worker0.93ms、暖几何捕获约0.159ms，仅证明局部可行，不代表整游戏收益；冷准备和真实采样范围见[BASELINE](baseline.md#共享空间读取的首批实施)。

开发期只维护最新存档，历史fixture/本机旧开发档已清理；支持范围查[compatibility](../engineering/compatibility.md)。门继续是可自由穿行、围合/隔热/遮光不变的墙体，锁门以后再说。原计算范式及已有频率仍有效，阶段不会借线程完成顺序改写因果。

## 工作区与受保护内容

短实验、临时检查与报告在忽略的logs；旧CI/长回归仍退役。`--suite spatial`增加一个毫秒级执行原语检查，没有全世界回归；真实植物变化及完整候选恢复另做一次临时短集成。没有改变业务周期或新增语言/GPU后端。

- 保留`codex/field-contest`（`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`）及其他已有工作分支。
- 原stash `424f956d280fb390d17e1f6dd879f3614b51a430`原样保留。
- 退役测试WIP仍在忽略的`logs/retired-test-workflow-20261111-012331/`，不恢复为任务。
