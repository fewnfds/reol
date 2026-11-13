# 当前接续

更新：2026-11-13。任意角度连续移动已完成review、短验证与release重建；地块环境、柔和视野、临时像素包和六段高速内核保留。Git状态优先，不在此重复登记提交号。

## 新接手入口

1. [FEATURES](features.md)：实际可玩能力、键位/路线与明确未完成范围。
2. [BASELINE](baseline.md)：当前release包、负载、帧时/实际倍率、异常窗口与证据。
3. [运行架构](../engineering/architecture.md)：原状态owner、共同时间/行动、CPU页批、显示/存读边界；新增计算按需查[计算接入](../engineering/execution-batches.md)。
4. [唯一主计划](../plans/foundation-priorities.md)：已交付阶段与当前试玩反馈；产品规则见[design/rules](../../design/rules/README.md)。

正式入口只有`scenes/main.tscn`。自主模拟线程持有World，worker独占身体页，UI只读脱离Frame；没有GameClock、活世界借还、旧GPU场回读或第二运行后端。功能已接回当前内核，不搬回旧框架；保留的旧JSON不自动表示启用能力。

## 当前停点

本轮底部锚点反馈已处理，源码与正式`build/windows/reol-demo.exe`/pck均已更新；实际图像/输入与同包性能记录见BASELINE首节。前轮连续移动及存读成果保留，不为本次显示调整迁移事实。提交交付后停在用户试玩反馈，不自动扩展新功能或继续优化。

实现咨询已完整收取并核查；最后追加整份代码顾问审阅耗尽推理预算、正文为空，已如实记录，不称为通过。没有仍待领取的顾问请求；本机失败记录保留，不重发旧问题。

- [共同导航](../engineering/architecture.md#连续移动与共同导航)负责连续目标、双相位原生格通路、身体净空、动态墙和带时间轨迹；原四向逐格心导航已替换。P路线预览可用，S停在当前位置。
- [运行与精度](../engineering/simulation-pacing.md)是周期、请求分批、AABB近似和过载语义正文。没有新增通用低优先级任务池、每人物节点或第二物理时钟；角色间仍可穿行，没有群体避让/编队。
- [地块分层](../engineering/architecture.md#地块与实体分层)保留自然基底/地被/地板、自然生境与清场分级；没有扩展持续野生扩散。感知仍供NPC/战斗共用，显示柔化不重做一套视线。
- [素材入口](../../assets/README.md)维护坐标/占地/接地点、实际留白切图、整格墙和四向家具的唯一说明。按最新反馈，世界精灵锚点已从占地中心改到占地底边中点，连续移动与鼠标/镜头/阴影同步；墙地板仍完整覆盖原占格。F8图鉴、F12诊断仍可用。
- 当前格式只查[compatibility](../engineering/compatibility.md)。连续目标/路线改变开发格式，用户原旧档保留，不建立迁移链；正式试玩请新开局。
- 原方案和实现咨询的取舍只归[研究](../../design/research/large_simulation_optimization.md#任意角度移动方案核查与实施)，问答/凭据留忽略的`.local/`，运行图像/失败记录留`logs/continuous-motion-20261113/`。

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
