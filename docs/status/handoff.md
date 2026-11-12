# 当前接续

更新：2026-11-12。本轮是基础运行框架根本重建；用户允许删除旧世界能力，以实测吞吐与真实倍率为首要出口。当前Git状态优先，本页不重复登记提交号。

## 新接手入口

1. [FEATURES](features.md)：当前能玩什么、键位，以及明确删除/未迁回的玩法。
2. [BASELINE](baseline.md)：release真实窗口、负载、硬件、容量限制与证据路径。
3. [运行架构](../engineering/architecture.md)：唯一原状态与线程/显示边界；新计算按需查[计算接入](../engineering/execution-batches.md)。
4. [唯一主计划](../plans/foundation-priorities.md)：本阶段出口与后续候选；产品规则保留在[design/rules](../../design/rules/README.md)。

正式入口只有`scenes/main.tscn`，世界由`sim/kernel/runner.gd`的自主线程持有。UI只读不可变Frame，不再有GameClock、世界借还、旧GPU场回读、旧完整领域后端或双运行模式。不要把保留的旧JSON当已启用玩法。SL和多项旧能力已明确退役，不能从历史文档恢复成这轮前置任务。

本轮九路顾问的原问题/回答及一手资料缓存放忽略的`.local/advisor/consultations/kernel-rebuild-20261112/`与`.local/advisor/runs/kernel-rebuild-20261112-*`，顾问用法只查根AGENTS提供的本机入口。六路研究、三路代码审查已结束，没有待重发的请求。采用与拒绝依据只维护在[研究](../../design/research/large_simulation_optimization.md)，回答不是事实依据或开发门禁。

## 当前停点

本轮实现、九次顾问核查、短反例、真实交互及最终release窗口已经完成，正式试玩包已重建。主计划本阶段已收尾；提交/主线位置以Git为准。接下来先体验并讨论恢复哪些玩法，不自动继续旧优化或从历史恢复任务。最终结果与未验证范围只看BASELINE。

重建前版本`a493bf0`保留在Git；本机旧代码快照在忽略的`logs/retired-runtime-20261112/`，无需恢复它才能开发。旧CI/长回归不恢复。

## 受保护内容

- 保留`codex/field-contest`（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 保留stash `424f956d280fb390d17e1f6dd879f3614b51a430`。
- 没有改写用户档、凭据、原始素材或第三方addon；本机顾问程序/配置不入库。
