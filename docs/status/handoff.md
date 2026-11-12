# 当前接续

更新：2026-11-12。高速基础内核重建及本轮六段功能恢复已交付，当前可先试玩反馈；本页不另留继续旧优化的待办。Git状态优先，不在此重复登记提交号。

## 新接手入口

1. [FEATURES](features.md)：实际可玩能力、键位/路线与明确未完成范围。
2. [BASELINE](baseline.md)：当前release包、负载、帧时/实际倍率、异常窗口与证据。
3. [运行架构](../engineering/architecture.md)：原状态owner、共同时间/行动、CPU页批、显示/存读边界；新增计算按需查[计算接入](../engineering/execution-batches.md)。
4. [唯一主计划](../plans/foundation-priorities.md)：本轮六段出口与后续取舍；产品规则见[design/rules](../../design/rules/README.md)。

正式入口只有`scenes/main.tscn`。自主模拟线程持有World，worker独占身体页，UI只读脱离Frame；没有GameClock、活世界借还、旧GPU场回读或第二运行后端。功能已接回当前内核，不搬回旧框架；保留的旧JSON不自动表示启用能力。

## 当前停点

实物/通用行动/SL、建筑与自主生活、自然植物、战斗/身体、交往修行、有限地区接续均有集成出口。实际能力和限制只维护在FEATURES，周期/近似见simulation-pacing；当前地区不是无限地图或远区LOD。最终review、重建、同包性能与全新进程读档证据归BASELINE。没有仍待领取的顾问请求，也没有需要恢复的旧CI/长回归。

本轮顾问原问答留忽略的`.local/advisor/consultations/restore-play-20261112-stage*/`及runs，采纳/拒绝理由见[研究页](../../design/research/large_simulation_optimization.md)。顾问会迎合和推断未提供代码，实际源码/测量优先；本机工具入口由根AGENTS发现，不上传程序或凭据。

重建前版本a493bf0由Git追溯，旧快照留忽略的`logs/retired-runtime-20261112/`。本轮未迁回的大项是后续候选，不因旧计划自动继续开发。

## 受保护内容

- 保留`codex/field-contest`（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 保留stash `424f956d280fb390d17e1f6dd879f3614b51a430`。
- 用户档、凭据、原始素材和第三方addon未改写；本机顾问与运行证据不入库。
