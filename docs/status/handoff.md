# 当前接续

更新：2026-11-11。最新用户已要求以**主要负载多核化**为当前开发主线，并要一份成熟项目经验支持的方案；此前“先讨论/试玩、停止扩展”停点已撤销。本次基于`22c3aa7`完成方案、运行窗口计数与有界独立寻路探针，主要线程/数据架构尚待实现。

当前阶段及交付顺序只看[主计划](../plans/foundation-priorities.md#当前阶段主要模拟负载多核化)，目标线程/数据/依赖结构看[执行方案](../specs/world-engine/execution.md)。下一小阶段从分块几何/身体读取和完整发布接口切入，解除活SceneTree、隐式同步getter与共享可变搜索上下文的耦合；随后模拟协调线程与实际主要计算批处理。不要把零散单线程微优化重新列为独立主线。

## 接手入口

- [计算范式](../engineering/settlement-contract.md#计算优化范式)是新增领域选择事件、周期、变脏、延后、续算及CPU/GPU路径的唯一正文；具体频率与宿主预算见[运行合同](../engineering/simulation-pacing.md)。
- [代码入口](../../scripts/README.md)、[owner表](../engineering/architecture/02-owners.md)定位原状态；[唯一计划](../plans/foundation-priorities.md)保留范围与暂停候选。
- [BASELINE](baseline.md)维护当前版本、测量及验证限制；旧性能实验在[历史记录](../archive/qa/20261111_performance_experiments.md)，不自动续做。

## 当前事实

普通运行仍复用现有共同时间、分频、CPU批/GPU场路径及呈现队列。新诊断表明300人45秒内原身体并行只有1批，主要算术覆盖很低；同步导航提供者又大量命中缓存，不能仅靠这两条小路径扩线程。详细数字、限制和来源见[BASELINE](baseline.md#多核主线的首轮核查)与[研究](../../design/research/large_simulation_optimization.md#多核执行2026-11-11)。

真实请求坐标的独立快照重放在4worker下约1.57×，结果一致；一次性准备输入却更贵，所以探针留在忽略的logs，没有进入普通游戏。新增`--profile-navigation`只在诊断模式跟踪原生/服务路径，身体批统计新增运行窗口差值，防止把装配阶段冒充持续并行。全游戏多核、线程CPU追踪和300人稳定60FPS都还未完成。

开发期只维护最新存档，历史fixture/本机旧开发档已清理；支持范围查[compatibility](../engineering/compatibility.md)。门继续是可自由穿行、围合/隔热/遮光不变的墙体，锁门以后再说。原计算范式及已有频率仍有效，阶段不会借线程完成顺序改写因果。

## 工作区与受保护内容

当前分支、dirty和远端以Git为准。短实验、临时检查与报告在忽略的logs；旧CI/长回归仍退役。本次普通运行没有新增业务线程或改变周期参数；诊断改动仅在工具入口使用。

- 保留`codex/field-contest`（`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`）及其他已有工作分支。
- 原stash `424f956d280fb390d17e1f6dd879f3614b51a430`原样保留。
- 退役测试WIP仍在忽略的`logs/retired-test-workflow-20261111-012331/`，不恢复为任务。
