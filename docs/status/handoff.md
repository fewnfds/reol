# 当前接续

更新：2026-11-12。本轮运行效率第一阶段已落地：拆分人物/环境等待与采样计数；删除物品画布每帧全量查询，以完整边界外观和轻量携带跟随分工。已完成release对照及相关功能接缝检查，结果和未测范围只查BASELINE；下一候选仍在唯一主计划，不自动开启全部重构。输入系统工作保留，尚未启用右键移动和A/S/H。分支、提交、推送和goal状态以工具为准。

## 接手入口

- [功能试游入口](../engineering/tooling/usage.md#功能试游)说明启动、存档和导览位置；体验步骤只在游戏内维护。[主计划](../plans/foundation-priorities.md)维护范围；[BASELINE](baseline.md)维护实测证据。
- [计算接入](../engineering/execution-batches.md)是直接领域逻辑、事件/分频、CPU批与GPU场的唯一选择指南，按需使用，不要求所有功能实现统一接口。具体领域只查[工程地图](../engineering/README.md)。
- [代码入口](../../scripts/README.md)、[owner表](../engineering/architecture/02-owners.md)定位原状态；[FEATURES](features.md)定位可玩操作。当前只支持最新存档，见[compatibility](../engineering/compatibility.md)。

## 本轮接续

世界事实、模型响应、采样精度与调度延迟的唯一概念正文在[运行与精度](../engineering/simulation-pacing.md#世界事实与计算精度)。旧全局同未来产品门槛已收窄；当前代码仍按完整共同边界推进，尚无任意玩法任务的跨步低优先级池。不要把新取舍当作已有异步实现，也不为“去确定性”删除便宜的稳定ID/量化/随机状态。

本轮改动入口是`WorldObjectsRuntime`、`object_marker_view.gd`及原`CommittedWorldCanvas`诊断；职责只见[呈现](../engineering/architecture/03-time-space-presentation.md)。本机没有待收取的压力进程或顾问请求。后续从[主计划](../plans/foundation-priorities.md#运行效率路线)的待选项选择，优先检查身体发布/采用减量或同截止环境变更合并。目击者索引实验无收益已撤回；未改共同结算频率/调度语义，也未实现跨步环境采用。顾问原件与临时探针留在本机忽略目录，公共文档只保留已核查取舍。

已交付试玩、数值HUD、固定外观迷雾记忆和忙碌点击修复，能力/操作只查FEATURES，验证只查BASELINE。试游继承普通Main，使用原领域及可选独立保存槽；没有新玩法后端。当前模型开发档仍需匹配最新版本，新开局要求查[兼容政策](../engineering/compatibility.md)。旧研究/测量在[历史](../archive/qa/README.md)，临时原件在忽略的logs；不恢复其任务。

## 受保护内容

- 保留codex/field-contest（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 原stash 424f956d280fb390d17e1f6dd879f3614b51a430原样保留。
- 退役测试WIP仍在logs/retired-test-workflow-20261111-012331/，不恢复。门仍自由穿行并保持房间，锁门后续再议。
