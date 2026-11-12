# 当前接续

更新：2026-11-12。高速基础内核重建、六段功能恢复及单位视野/迷雾修复已交付；可继续源码试玩反馈。Git状态优先，不在此重复登记提交号。

## 新接手入口

1. [FEATURES](features.md)：实际可玩能力、键位/路线与明确未完成范围。
2. [BASELINE](baseline.md)：当前release包、负载、帧时/实际倍率、异常窗口与证据。
3. [运行架构](../engineering/architecture.md)：原状态owner、共同时间/行动、CPU页批、显示/存读边界；新增计算按需查[计算接入](../engineering/execution-batches.md)。
4. [唯一主计划](../plans/foundation-priorities.md)：本轮六段出口与后续取舍；产品规则见[design/rules](../../design/rules/README.md)。

正式入口只有`scenes/main.tscn`。自主模拟线程持有World，worker独占身体页，UI只读脱离Frame；没有GameClock、活世界借还、旧GPU场回读或第二运行后端。功能已接回当前内核，不搬回旧框架；保留的旧JSON不自动表示启用能力。

## 当前停点

最新试玩“世界运行但玩家不能动”已从所读快速档确认玩家#1在世界416秒时HP0/DEAD，原UI缺少死亡与拒绝提示。现已补独立F12诊断面板、玩家常驻状态/回执和角色身体拾取；操作与日志归[运行与测量](../engineering/tooling/usage.md)，排查/短探针证据留忽略的`logs/live-movement-20261112/`。未主动关闭用户原窗口或改写原存档；新面板需重开源码进程，死因尚未从该旧档确认。

单位视野与战斗感知阶段已接共同几何、最后所见/盲区反击、分散警戒、CPU查询批和玩家格图/静态记忆。临时纯圆与旧GPU逐像素判定均已退出。实现只查[架构](../engineering/architecture.md)，阶段已在[唯一主计划](../plans/foundation-priorities.md#当前试玩反馈单位视野与迷雾)收尾；没有待恢复的优化goal或仍待领取的顾问请求。

最后两次顾问已用用户指定的顶层`thinking: high`并完整收取；本机客户端和说明同步更新，程序/凭据/问答不入库。原问答在忽略的`.local/advisor/runs/unit-sight-20261112-*`，取舍只查[研究页](../../design/research/large_simulation_optimization.md#全单位感知与战斗视野咨询)。

短检查和结构审查通过，最终release单独导出到`build/sight-candidate`并测量，千人混合4×复查达到请求流速与60FPS，保留一次未定位的67ms画面尖峰；完整数据与局限只查BASELINE。根`开发试玩.cmd`从最新源码启动；`build/windows`仍是上一轮快照，不会自动读取源码。视距、战斗接触与最后所见地表已进入当前开发格式，不迁移旧开发档；没有删除用户原档。

## 已交付背景

实物/通用行动/SL、建筑与自主生活、自然植物、战斗/身体、交往修行、有限地区接续均有集成出口。实际能力和限制只维护在FEATURES，周期/近似见simulation-pacing；当前地区不是无限地图或远区LOD。最终review、重建、同包性能与全新进程读档证据归BASELINE。没有仍待领取的顾问请求，也没有需要恢复的旧CI/长回归。

本轮顾问原问答留忽略的`.local/advisor/consultations/restore-play-20261112-stage*/`及runs，采纳/拒绝理由见[研究页](../../design/research/large_simulation_optimization.md)。顾问会迎合和推断未提供代码，实际源码/测量优先；本机工具入口由根AGENTS发现，不上传程序或凭据。

重建前版本a493bf0由Git追溯，旧快照留忽略的`logs/retired-runtime-20261112/`。本轮未迁回的大项是后续候选，不因旧计划自动继续开发。

## 受保护内容

- 保留`codex/field-contest`（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 保留stash `424f956d280fb390d17e1f6dd879f3614b51a430`。
- 用户档、凭据、原始素材和第三方addon未改写；本机顾问与运行证据不入库。
