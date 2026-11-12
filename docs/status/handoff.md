# 当前接续

更新：2026-11-12。基础运行框架重建已完成，当前转入功能恢复规划；用户允许体验接近旧版、后端完全重构。当前Git状态优先，本页不重复登记提交号。

## 新接手入口

1. [FEATURES](features.md)：当前能玩什么、键位，以及明确删除/未迁回的玩法。
2. [BASELINE](baseline.md)：release真实窗口、负载、硬件、容量限制与证据路径。
3. [运行架构](../engineering/architecture.md)：唯一原状态与线程/显示边界；新计算按需查[计算接入](../engineering/execution-batches.md)。
4. [唯一主计划](../plans/foundation-priorities.md)：功能添加顺序与首段可玩出口；产品规则保留在[design/rules](../../design/rules/README.md)。

正式入口只有`scenes/main.tscn`，世界由`sim/kernel/runner.gd`的自主线程持有。UI只读不可变Frame，不再有GameClock、世界借还、旧GPU场回读、旧完整领域后端或双运行模式。不要把保留的旧JSON当已启用玩法；SL等当前未恢复能力按主计划重做，不搬回旧框架。

重建九路顾问与功能恢复两路顾问均已正常结束，没有待重发的请求。功能恢复原问题/核查在忽略的`.local/advisor/consultations/feature-return-20261112/`，原回答在`.local/advisor/runs/feature-return-20261112-*`；顾问用法只查根AGENTS提供的本机入口。采用与拒绝依据只维护在[研究](../../design/research/large_simulation_optimization.md)，回答不是事实依据或开发门禁。

## 当前停点

重建的正式试玩包与测量仍有效，最终结果与未验证范围只看BASELINE。本轮仅更新唯一主计划和研究取舍，没有恢复功能或重建试玩包；下一次开发从主计划第一段“实物交互与可接续会话”开始，按可玩闭环交付，不继续旧优化队列。

重建前版本`a493bf0`保留在Git；本机旧代码快照在忽略的`logs/retired-runtime-20261112/`，无需恢复它才能开发。旧CI/长回归不恢复。

## 受保护内容

- 保留`codex/field-contest`（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 保留stash `424f956d280fb390d17e1f6dd879f3614b51a430`。
- 没有改写用户档、凭据、原始素材或第三方addon；本机顾问程序/配置不入库。
