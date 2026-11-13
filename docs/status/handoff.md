# 当前接续

更新：2026-11-13。连续视野显示、8×/16×入口与有界性能核查已交付；人物/装备/背包只形成待确认方案，未开始相应领域开发。此前UI、个人事件、耐受及高速内核保留。Git状态优先，不在此重复登记提交号。

## 新接手入口

1. [FEATURES](features.md)：实际可玩能力、键位/路线与明确未完成范围。
2. [BASELINE](baseline.md)：当前release包、负载、帧时/实际倍率、异常窗口与证据。
3. [运行架构](../engineering/architecture.md)：原状态owner、共同时间/行动、CPU页批、显示/存读边界；新增计算按需查[计算接入](../engineering/execution-batches.md)。
4. [唯一主计划](../plans/foundation-priorities.md)：已交付阶段与当前试玩反馈；产品规则见[design/rules](../../design/rules/README.md)。

正式入口只有`scenes/main.tscn`。自主模拟线程持有World，worker独占身体页，UI只读脱离Frame；没有GameClock、活世界借还、旧GPU场回读或第二运行后端。功能已接回当前内核，不搬回旧框架；保留的旧JSON不自动表示启用能力。

## 当前停点

最新反馈已修复视野圆心随整格跳动：保留原CPU观察/记忆，用共享损耗纹理与人物同一显示轨迹在GPU绘制连续柔边。更密CPU采样/四邻缓存曾实测成本过高，已撤掉；最终代码没有额外CPU视野图或亚格逻辑时钟，精度只查simulation-pacing。8×/16×已开放，普通24人能跑满，千人混合约4.4～4.5×容量封顶；正式同包窗口、移动中帧尖峰和拒绝实验归BASELINE首节。

背包提案只维护在[唯一主计划首节](../plans/foundation-priorities.md#下一项建议人物装备与背包)：建议人物装备＋核心属性同窗、背包可独立/并排，图标格显示数量品质。尚未实现装备/品质、修改容量或决定完整属性公式；用户这次要方案，不把提案当已批准的新开发任务。

首版RTS/MOBA指挥与环世界式对象操作之后，本轮已完成固定地块探针、命令台贴底、缩小默认UI与数字缩放确认、中文人物事件，以及先耐受后HP的冷热缓冲。黄圈是主控、青蓝圈是选中，彩色移动场源圈改为DEV显示；界面只保留按钮、图标、状态和数值。能力与参数分别只查FEATURES和simulation-pacing，[主计划](../plans/foundation-priorities.md#已交付可用的ui与交互)已更新交付状态。

新入口在`scripts/presentation/ui/`：HUD、交互、中文事件显示、命令适用与分层小地图各有职责，见[架构](../engineering/architecture.md#交互与小地图)。人物事实沿World.emit进入有界冷记录，不另造结算引擎；worker只写独占身体页。UI独立缩放，不改相机，物资列表已改内嵌ItemList以保持一致比例。

原`(207,195)`冷源已由修改前探针定位为随机压力场源混入普通局；普通局不再装配随机静态/移动源，Regions两个无实体演示源也删除。地区背景、天气和真实植物排放保留；混合压力局显式启用原随机源。身体冷热耐受没有扩展为战斗护盾或完整抗性系统。

源码与正式`build/windows/reol-demo.exe`/pck均已更新。kernel、按需体验/图形UI短检查通过；同最终包千人4×/60FPS与普通120FPS窗口、前轮未定位帧尖峰和验证范围见BASELINE首节。后续从实际试玩反馈选择主题，不将短窗当长局保证。

本机顾问客户端已落实同一提示词双模型并发、各一次非流式且失败不重试，说明只维护在`.local/advisor/README.md`。视野/高倍速/背包同题两答已完整收齐，取舍留`.local/advisor/consultations/sight-speed-inventory-20261113/review.md`及原runs；上一轮体验咨询仍在`ui-experience-20261113`。没有待收取请求，不上传程序、凭据或问答。

共同导航、地块分层与世界呈现仍由原架构页解释；周期/近似与耐受只查[运行与精度](../engineering/simulation-pacing.md)，素材接地点只查[assets](../../assets/README.md)，本轮新增身体/日志原状态后的当前存档支持只查[compatibility](../engineering/compatibility.md)。旧档保留，本版需新开局，没有恢复旧运行后端。

源码入口是根`开发试玩.cmd`，需重开进程读取最新脚本；独立exe/pck只代表导出时快照，不热读源码。实际键位、完成范围和限制分别维护于FEATURES/BASELINE，不再附加第二份继续开发清单。后续按用户试玩反馈选择主题，不自动恢复旧CI或继续无限优化。

此前“世界仍运行但玩家不动”从快速档确认#1 HP0/DEAD；独立提示、F12诊断和倒地精灵保留，旧档最后伤害来源仍不能由旧日志确定，不能倒推为已证实冻死。本轮开始记录真实伤害与死因。未主动关闭用户旧游戏或改写原档；诊断只查[运行与测量](../engineering/tooling/usage.md)。

## 已交付背景

实物/通用行动/SL、建筑与自主生活、自然植物、战斗/身体、交往修行、有限地区接续均有集成出口。实际能力和限制只维护在FEATURES，周期/近似见simulation-pacing；当前地区不是无限地图或远区LOD。最终review、重建、同包性能与全新进程读档证据归BASELINE。旧CI/长回归不恢复，本轮收尾状态以上节为准。

本轮顾问原问答留忽略的`.local/advisor/consultations/restore-play-20261112-stage*/`及runs，采纳/拒绝理由见[研究页](../../design/research/large_simulation_optimization.md)。顾问会迎合和推断未提供代码，实际源码/测量优先；本机工具入口由根AGENTS发现，不上传程序或凭据。

重建前版本a493bf0由Git追溯，旧快照留忽略的`logs/retired-runtime-20261112/`。本轮未迁回的大项是后续候选，不因旧计划自动继续开发。

## 受保护内容

- 保留`codex/field-contest`（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 保留stash `424f956d280fb390d17e1f6dd879f3614b51a430`。
- 用户档、凭据、原始素材和第三方addon未改写；本机顾问与运行证据不入库。
