# 当前接续

更新：2026-11-11。本阶段在`84bfdda`的分频与可穿行门基础上收尾。最新用户重点是建立可扩展的计算优化范式，允许眼下收益有限；已落实到原结算合同及实际呈现工作队列，相关短检查和300人release对照完成。接下来先讨论/试玩，不自动展开新一轮性能重构。

## 接手入口

- [计算范式](../engineering/settlement-contract.md#计算优化范式)是新增领域选择事件、周期、变脏、延后、续算及CPU/GPU路径的唯一正文；具体频率与宿主预算见[运行合同](../engineering/simulation-pacing.md)。
- [代码入口](../../scripts/README.md)、[owner表](../engineering/architecture/02-owners.md)定位原状态；[唯一计划](../plans/foundation-priorities.md)保留范围与暂停候选。
- [BASELINE](baseline.md)维护当前版本、测量及验证限制；旧性能实验在[历史记录](../archive/qa/20261111_performance_experiments.md)，不自动续做。

## 当前事实

现有逻辑频率、共同因果及CPU/GPU执行继续复用。新增`ReolPresentationWork`只处理可重建呈现，已接地形预绘和光照：合并、可见/后台优先、预算延期与等待提升。它不推进世界、保存探索或任意推迟已受理效果；未完成世界仍不能被光照查询。当前仍有旧域原子回调，未宣称全域增量化。

300人45秒同命令release前后流速约0.990×/0.992×，P99约20.10/19.31ms，最大帧与超时帧数没有同步改善。后台区块预绘完成更晚，可见地形不走延期预算；具体限制见BASELINE。稳定60FPS尚未达成。

用户明确开发期只留最新存档：仓库历史fixture、本机已确认过时的开发档及旧认识账本兼容已清理，不再生成版本收藏。当前格式与原子写入政策只查[compatibility](../engineering/compatibility.md)。门继续是可自由穿行、围合/隔热/遮光不变的墙体；锁门以后再说。

## 工作区与受保护内容

当前分支、dirty和远端以Git为准。短实验、临时检查与报告在忽略的logs；旧CI/长回归仍退役。本次没有修改玩法周期参数或引入新设备后端。

- 保留`codex/field-contest`（`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`）及其他已有工作分支。
- 原stash `424f956d280fb390d17e1f6dd879f3614b51a430`原样保留。
- 退役测试WIP仍在忽略的`logs/retired-test-workflow-20261111-012331/`，不恢复为任务。
