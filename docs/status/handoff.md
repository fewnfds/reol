# 当前接续

更新：2026-11-12。基础运行框架重建已完成，当前执行功能恢复goal；用户允许体验接近旧版、后端完全重构。当前Git状态优先，本页不重复登记提交号。

## 新接手入口

1. [FEATURES](features.md)：当前能玩什么、键位，以及明确删除/未迁回的玩法。
2. [BASELINE](baseline.md)：release真实窗口、负载、硬件、容量限制与证据路径。
3. [运行架构](../engineering/architecture.md)：唯一原状态与线程/显示边界；新计算按需查[计算接入](../engineering/execution-batches.md)。
4. [唯一主计划](../plans/foundation-priorities.md)：功能添加顺序与首段可玩出口；产品规则保留在[design/rules](../../design/rules/README.md)。

正式入口只有`scenes/main.tscn`，世界由`sim/kernel/runner.gd`的自主线程持有。UI只读不可变Frame，不再有GameClock、世界借还、旧GPU场回读、旧完整领域后端或双运行模式。不要把保留的旧JSON当已启用玩法；SL等当前未恢复能力按主计划重做，不搬回旧框架。

## 当前停点

完整功能恢复goal仍active。第1、2段已交付真实物资/容器、通用接近/耗时/取消、当前会话SL、材料蓝图/多格设施与有限个人线索自主生活，正开始第3段环境植物。进度与后续顺序只维护在唯一主计划；能力、未迁回范围和真实性能分别看FEATURES、BASELINE。

本轮顾问请求/答复留忽略的`.local/advisor/consultations/restore-play-20261112-stage*/`与同名runs。已收首两段方案/反例/审查，第3段设计已收，第4段设计异步进行中；原进程以会话状态为准，不因非流式等待重发。采用与拒绝看研究页，顾问不是事实依据。特别已用本机4.7.2测出rename覆盖已有文件成功，且lane是WorkerThreadPool任务上下文，不是需关闭的驻留Thread；不要照搬顾问相反断言。

基础重建前版本`a493bf0`保留在Git，本机旧快照在忽略的`logs/retired-runtime-20261112/`；不恢复旧运行框架、CI/长回归或旧档迁移。

## 受保护内容

- 保留`codex/field-contest`（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 保留stash `424f956d280fb390d17e1f6dd879f3614b51a430`。
- 没有改写用户档、凭据、原始素材或第三方addon；本机顾问程序/配置不入库。
