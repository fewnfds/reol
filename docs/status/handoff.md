# 当前接续

更新：2026-11-12。临时像素视觉包、高速内核六段功能恢复及单位视野/迷雾修复已交付；可继续源码试玩反馈。Git状态优先，不在此重复登记提交号。

## 新接手入口

1. [FEATURES](features.md)：实际可玩能力、键位/路线与明确未完成范围。
2. [BASELINE](baseline.md)：当前release包、负载、帧时/实际倍率、异常窗口与证据。
3. [运行架构](../engineering/architecture.md)：原状态owner、共同时间/行动、CPU页批、显示/存读边界；新增计算按需查[计算接入](../engineering/execution-batches.md)。
4. [唯一主计划](../plans/foundation-priorities.md)：本轮六段出口与后续取舍；产品规则见[design/rules](../../design/rules/README.md)。

正式入口只有`scenes/main.tscn`。自主模拟线程持有World，worker独占身体页，UI只读脱离Frame；没有GameClock、活世界借还、旧GPU场回读或第二运行后端。功能已接回当前内核，不搬回旧框架；保留的旧JSON不自动表示启用能力。

## 当前停点

临时Q版像素视觉阶段完成，正式`build/windows/reol-demo.exe`和pck已重建；源码入口仍是根`开发试玩.cmd`，需重开进程读取本轮素材/脚本，既有exe不会热读源码。没有待继续的美术或优化goal，也没有未收取的顾问请求。下一步等用户实际试玩反馈，不自动继续补预备动物玩法。

- [素材入口](../../assets/README.md)是本轮唯一覆盖/来源/重建正文；512个人物动作格、169地物/物品/特效切片、32地形切片已取得并接线，预备与未实现玩法明确分开。F8图鉴可看全部，F12仍是独立诊断。
- [BASELINE](baseline.md)记录最终release哈希和千人混合4×/60FPS对照、24人120FPS、实际画面与短反例。新显示增加了少量CPU成本，目标流速和帧率没有明显回退；未承诺低配长局或完整动物动画。
- [当前架构](../engineering/architecture.md)标记Art/Frame.Visual、图集批绘、昼夜天气和原有迷雾的边界。旧HumanoidAppearance读取器已退出；原创旧样本/生成器只保留作历史源资产，不随Demo导出、不形成兼容任务。
- 两次Argon顾问（thinking:high、131072预算）和4次生图都已完整收取；公开取舍只归[研究页](../../design/research/large_simulation_optimization.md#临时像素美术的清单与源码核查)。原请求/凭据/下载评估留忽略的`.local/`，不上传。

此前“世界仍运行但玩家不动”从所读快速档确认#1 HP0/DEAD；现有独立状态提示/诊断加上本轮倒地精灵，不再只站着。未改写用户原档或主动关闭原试玩进程；该旧档具体最后伤害来源仍无法由旧日志确定。诊断命令只查[运行与测量](../engineering/tooling/usage.md)。

## 已交付背景

实物/通用行动/SL、建筑与自主生活、自然植物、战斗/身体、交往修行、有限地区接续均有集成出口。实际能力和限制只维护在FEATURES，周期/近似见simulation-pacing；当前地区不是无限地图或远区LOD。最终review、重建、同包性能与全新进程读档证据归BASELINE。没有仍待领取的顾问请求，也没有需要恢复的旧CI/长回归。

本轮顾问原问答留忽略的`.local/advisor/consultations/restore-play-20261112-stage*/`及runs，采纳/拒绝理由见[研究页](../../design/research/large_simulation_optimization.md)。顾问会迎合和推断未提供代码，实际源码/测量优先；本机工具入口由根AGENTS发现，不上传程序或凭据。

重建前版本a493bf0由Git追溯，旧快照留忽略的`logs/retired-runtime-20261112/`。本轮未迁回的大项是后续候选，不因旧计划自动继续开发。

## 受保护内容

- 保留`codex/field-contest`（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 保留stash `424f956d280fb390d17e1f6dd879f3614b51a430`。
- 用户档、凭据、原始素材和第三方addon未改写；本机顾问与运行证据不入库。
