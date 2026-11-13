# 当前接续

更新：2026-11-13。地块分层/生境和柔和视野已落地，第二轮截图的天气方向、源图列裁边、整格墙、轴对齐四向家具、中心接地与接触影已修复；高速内核六段与临时像素包仍用同一后端。Git状态优先，不在此重复登记提交号。

## 新接手入口

1. [FEATURES](features.md)：实际可玩能力、键位/路线与明确未完成范围。
2. [BASELINE](baseline.md)：当前release包、负载、帧时/实际倍率、异常窗口与证据。
3. [运行架构](../engineering/architecture.md)：原状态owner、共同时间/行动、CPU页批、显示/存读边界；新增计算按需查[计算接入](../engineering/execution-batches.md)。
4. [唯一主计划](../plans/foundation-priorities.md)：已交付阶段与当前试玩反馈；产品规则见[design/rules](../../design/rules/README.md)。

正式入口只有`scenes/main.tscn`。自主模拟线程持有World，worker独占身体页，UI只读脱离Frame；没有GameClock、活世界借还、旧GPU场回读或第二运行后端。功能已接回当前内核，不搬回旧框架；保留的旧JSON不自动表示启用能力。

## 当前停点

本轮地块/视觉反馈已处理，正式`build/windows/reol-demo.exe`和pck已重建；源码入口仍是根`开发试玩.cmd`，需重开进程读取本轮素材/脚本，既有exe不会热读源码。最新用户要求讨论任意角度移动，当前只有[待实施方案](../plans/foundation-priorities.md#待实施方案任意角度移动与共同导航)，未改运行代码；已确认禁斜向、命令取整及逐格心跟随。用户恢复顾问服务后已重试成功、全文核查并更新取舍，没有待收回答；首选格通路/连续路线并以净空反例和原生NavServer对照选型。没有活动goal，不自动开始实现或扩展持续生态。

- [当前架构](../engineering/architecture.md#地块与实体分层)是基底/地被/地板、自然生境与植被清场的实现正文；人工盆栽、玩家后来围起的原有植物与地板拆除分层保留。自然撒布尚不等于持续野生扩散。
- [素材入口](../../assets/README.md)是坐标/占地/接地点、实际留白切图、整格墙和四向家具的唯一说明；程序家具在`tools/pixel_fixtures.py`，不是旋转斜透视图。完整树与人物共用批绘，墙门自动选图。F8图鉴、F12诊断仍可用。
- 四向建造下拉框会影响多格占地、外观与存读；现有`reol-world-4`继续使用，未引入旧档迁移。上一轮南缘放置偏移、窄十字墙、固定列宽预裁与压缩轮廓影已替换，没有并存的兼容显示路径。
- [BASELINE](baseline.md)首节记录本轮最终release哈希、千人混合全图4×、24人迷雾120FPS和图像/短反例，前轮迷雾压力窗口另列。排序增加了实际CPU成本，当前短窗目标流速/帧率没有明显回退；不承诺低配长局或任意负载同速。
- 感知仍全单位共用，柔和显示不是另一套战斗视线；周期和近似只查[运行与精度](../engineering/simulation-pacing.md)。开发HUD新增基底/地被/地板原值。
- 当前格式只查[compatibility](../engineering/compatibility.md)，原用户旧档未清理。第二轮顾问已经完整收取，本机`visual-coordinates-20261113`咨询的取舍只归[研究页](../../design/research/large_simulation_optimization.md#第二轮截图方向裁边和地面接触)，原请求/回答/凭据留忽略的`.local/`。

此前“世界仍运行但玩家不动”从所读快速档确认#1 HP0/DEAD；现有独立状态提示/诊断加上本轮倒地精灵，不再只站着。未改写用户原档或主动关闭原试玩进程；该旧档具体最后伤害来源仍无法由旧日志确定。诊断命令只查[运行与测量](../engineering/tooling/usage.md)。

## 已交付背景

实物/通用行动/SL、建筑与自主生活、自然植物、战斗/身体、交往修行、有限地区接续均有集成出口。实际能力和限制只维护在FEATURES，周期/近似见simulation-pacing；当前地区不是无限地图或远区LOD。最终review、重建、同包性能与全新进程读档证据归BASELINE。没有仍待领取的顾问请求，也没有需要恢复的旧CI/长回归。

本轮顾问原问答留忽略的`.local/advisor/consultations/restore-play-20261112-stage*/`及runs，采纳/拒绝理由见[研究页](../../design/research/large_simulation_optimization.md)。顾问会迎合和推断未提供代码，实际源码/测量优先；本机工具入口由根AGENTS发现，不上传程序或凭据。

重建前版本a493bf0由Git追溯，旧快照留忽略的`logs/retired-runtime-20261112/`。本轮未迁回的大项是后续候选，不因旧计划自动继续开发。

## 受保护内容

- 保留`codex/field-contest`（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 保留stash `424f956d280fb390d17e1f6dd879f3614b51a430`。
- 用户档、凭据、原始素材和第三方addon未改写；本机顾问与运行证据不入库。
