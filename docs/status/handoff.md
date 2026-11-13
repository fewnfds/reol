# 当前接续

更新：2026-11-13。可用UI、交互与地形小地图已实施、review并重建正式试玩包；任意角度移动、底部锚点及此前release成果保留。Git状态优先，不在此重复登记提交号。

## 新接手入口

1. [FEATURES](features.md)：实际可玩能力、键位/路线与明确未完成范围。
2. [BASELINE](baseline.md)：当前release包、负载、帧时/实际倍率、异常窗口与证据。
3. [运行架构](../engineering/architecture.md)：原状态owner、共同时间/行动、CPU页批、显示/存读边界；新增计算按需查[计算接入](../engineering/execution-batches.md)。
4. [唯一主计划](../plans/foundation-priorities.md)：已交付阶段与当前试玩反馈；产品规则见[design/rules](../../design/rules/README.md)。

正式入口只有`scenes/main.tscn`。自主模拟线程持有World，worker独占身体页，UI只读脱离Frame；没有GameClock、活世界借还、旧GPU场回读或第二运行后端。功能已接回当前内核，不搬回旧框架；保留的旧JSON不自动表示启用能力。

## 当前停点

用户确认方案后已完成RTS/MOBA指挥与环世界式对象操作的首版UI。界面只用按钮、图标、状态与数值表达，不添加备注、副标题和面板解释；属性/装备仍未定，不伪造多控、队列或物流。实际操作只维护在FEATURES，[主计划](../plans/foundation-priorities.md#已交付可用的ui与交互)已改为交付状态。

新入口在`scripts/presentation/ui/`：HUD、交互、命令词汇和分层小地图各有职责，见[架构](../engineering/architecture.md#交互与小地图)。小地图复用地形/迷雾纹理、缓存静物并降频整理可见人物点，不增加第二相机。建造/种植是单次放置并开工，回执区分已创建对象与后续行动受理；普通详情不泄露迷雾后的实时库存。

源码与正式`build/windows/reol-demo.exe`/pck均已更新。图形UI短探针与kernel smoke通过；正式包千人4×/普通120FPS窗口及未定位帧尖峰、显示/隐藏HUD对照、验证范围见BASELINE首节。后续从实际试玩反馈选择主题，不将短窗当长局保证。

本机顾问布局/交互/交付三题与实施补充两题均已收齐。并发隔离one-shot的说明已写入`.local/advisor/README.md`，取舍留`.local/advisor/consultations/ui-interaction-20261113/review.md`及原runs；没有待收取请求，不上传程序、凭据或问答。

共同导航、地块分层与世界呈现仍由原架构页解释；周期/近似只查[运行与精度](../engineering/simulation-pacing.md)，素材接地点只查[assets](../../assets/README.md)，当前存档格式只查[compatibility](../engineering/compatibility.md)。本轮没有新增玩法、改存档格式或恢复旧运行后端。

源码入口是根`开发试玩.cmd`，需重开进程读取最新脚本；独立exe/pck只代表导出时快照，不热读源码。实际键位、完成范围和限制分别维护于FEATURES/BASELINE，不再附加第二份继续开发清单。后续按用户试玩反馈选择主题，不自动恢复旧CI或继续无限优化。

此前“世界仍运行但玩家不动”从快速档确认#1 HP0/DEAD；现有独立提示、F12诊断和倒地精灵保留，旧档最后伤害来源仍不能由旧日志确定。未主动关闭用户旧游戏或改写原档；诊断只查[运行与测量](../engineering/tooling/usage.md)。

## 已交付背景

实物/通用行动/SL、建筑与自主生活、自然植物、战斗/身体、交往修行、有限地区接续均有集成出口。实际能力和限制只维护在FEATURES，周期/近似见simulation-pacing；当前地区不是无限地图或远区LOD。最终review、重建、同包性能与全新进程读档证据归BASELINE。旧CI/长回归不恢复，本轮收尾状态以上节为准。

本轮顾问原问答留忽略的`.local/advisor/consultations/restore-play-20261112-stage*/`及runs，采纳/拒绝理由见[研究页](../../design/research/large_simulation_optimization.md)。顾问会迎合和推断未提供代码，实际源码/测量优先；本机工具入口由根AGENTS发现，不上传程序或凭据。

重建前版本a493bf0由Git追溯，旧快照留忽略的`logs/retired-runtime-20261112/`。本轮未迁回的大项是后续候选，不因旧计划自动继续开发。

## 受保护内容

- 保留`codex/field-contest`（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 保留stash `424f956d280fb390d17e1f6dd879f3614b51a430`。
- 用户档、凭据、原始素材和第三方addon未改写；本机顾问与运行证据不入库。
