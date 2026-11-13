# 当前接续

更新：2026-11-13。人物/装备/格子背包已接通；自动容量搜索也已完成，结果和判据只查[BASELINE](baseline.md#当前自动容量搜索capacity-v1)，不要把旧报告或短窗FPS当作世界倍率上限。Git状态优先，不在此重复登记提交号。

## 新接手入口

1. [FEATURES](features.md)：实际可玩能力、键位/路线与明确未完成范围。
2. [BASELINE](baseline.md)：当前release包、负载、帧时/实际倍率、异常窗口与证据。
3. [运行架构](../engineering/architecture.md)：原状态owner、共同时间/行动、CPU页批、显示/存读边界；新增计算按需查[计算接入](../engineering/execution-batches.md)。
4. [唯一主计划](../plans/foundation-priorities.md)：已交付阶段与当前试玩反馈；产品规则见[design/rules](../../design/rules/README.md)。

正式入口只有`scenes/main.tscn`。自主模拟线程持有World，worker独占身体页，UI只读脱离Frame；没有GameClock、活世界借还、旧GPU场回读或第二运行后端。功能已接回当前内核，不搬回旧框架；保留的旧JSON不自动表示启用能力。

## 当前停点

人物/装备/背包已由提案进入实现，唯一计划首节已更新。Objects持有库存和穿戴位置，Items解释品质堆键，Equipment只在冷变更时重建身体属性热列；没有逐步装备扫描或第二份物品账本。UI入口在`presentation/ui/{character_panel,inventory_panel,item_grid}.gd`；人物与背包可分别开关、容器共用网格，NPC观察不授权控制。操作/样例与限制只看FEATURES，职责只看架构。

自动极限搜索入口`tools/capacity.py`，同包真实窗口串行，程序自己探边/二分/长窗确认并增量留结果；用原算法和明确持久压力初值，不让单位死亡/任务耗尽伪装性能。当前确认区间为1× 4600、2× 2000、4× 900、8× 400、16× 200，下一档分别为4700、2100、1000、500、300；测量方法/判据只看usage，容量和证据只回写BASELINE。它不属于默认smoke/CI，不重复启动旧长回归。

新开发存档范围只看[compatibility](../engineering/compatibility.md)：原档保留，本版需新开局，缓存按源事实重建。共同时间/近似和冷热耐受查[运行与精度](../engineering/simulation-pacing.md)，临时图集/程序图标查[assets](../../assets/README.md)；不在这里重复数值或建立第二份待办。

前轮连续GPU显示柔边、CPU逻辑观察/静态记忆、固定地块探针、底部指挥/缩放、中文个人事件、冷热耐受和普通局/压力源分离均保留。更密CPU视野采样曾被实测拒绝，未回迁；冷源根因、移动帧尖峰与旧包比较留BASELINE历史章节，不自动继续优化。

本机顾问同题双模型并发、各一次非流式、失败不重试，说明只在`.local/advisor/README.md`。本轮两答已收齐，核查在`.local/advisor/consultations/equipment-capacity-20261113/review.md`，无待收取请求；原问答、凭据与程序不入库，不把顾问的“必须”升级成项目规则。

源码试玩入口是根`开发试玩.cmd`，重开读取脚本；exe/pck是导出时快照。F12与[usage](../engineering/tooling/usage.md)提供诊断。此前角色不动已从旧档确认HP0/DEAD，旧日志不足以确定最后死因；当前独立死亡姿态、提示与真实伤害记录保留。未关闭用户旧游戏或改写用户原档。

## 已交付背景

实物/通用行动/SL、建筑与自主生活、自然植物、战斗/身体、交往修行、有限地区接续均有集成出口。实际能力和限制只维护在FEATURES，周期/近似见simulation-pacing；当前地区不是无限地图或远区LOD。最终review、重建、同包性能与全新进程读档证据归BASELINE。旧CI/长回归不恢复，本轮收尾状态以上节为准。

本轮顾问原问答留忽略的`.local/advisor/consultations/restore-play-20261112-stage*/`及runs，采纳/拒绝理由见[研究页](../../design/research/large_simulation_optimization.md)。顾问会迎合和推断未提供代码，实际源码/测量优先；本机工具入口由根AGENTS发现，不上传程序或凭据。

重建前版本a493bf0由Git追溯，旧快照留忽略的`logs/retired-runtime-20261112/`。本轮未迁回的大项是后续候选，不因旧计划自动继续开发。

## 受保护内容

- 保留`codex/field-contest`（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 保留stash `424f956d280fb390d17e1f6dd879f3614b51a430`。
- 用户档、凭据、原始素材和第三方addon未改写；本机顾问与运行证据不入库。
