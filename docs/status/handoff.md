# 当前接续

更新：2026-11-12。当前完成运行效率取舍、代码审阅与顾问核查，已更新唯一主计划；本轮只改文档，没有实施性能候选或新增运行测量。后续先讨论/安排实施，输入系统工作仍保留，尚未启用右键移动和A/S/H。没有active或paused goal；分支、提交和推送状态以Git为准。

## 接手入口

- [功能试游入口](../engineering/tooling/usage.md#功能试游)说明启动、存档和导览位置；体验步骤只在游戏内维护。[主计划](../plans/foundation-priorities.md)维护范围；[BASELINE](baseline.md)维护实测证据。
- [计算接入](../engineering/execution-batches.md)是直接领域逻辑、事件/分频、CPU批与GPU场的唯一选择指南，按需使用，不要求所有功能实现统一接口。具体领域只查[工程地图](../engineering/README.md)。
- [代码入口](../../scripts/README.md)、[owner表](../engineering/architecture/02-owners.md)定位原状态；[FEATURES](features.md)定位可玩操作。当前只支持最新存档，见[compatibility](../engineering/compatibility.md)。

## 本轮接续

世界事实、模型响应、采样精度与调度延迟的唯一概念正文在[运行与精度](../engineering/simulation-pacing.md#世界事实与计算精度)。旧全局同未来产品门槛已收窄；当前代码仍按完整共同边界推进，尚无任意玩法任务的跨步低优先级池。不要把新取舍当作已有异步实现，也不为“去确定性”删除便宜的稳定ID/量化/随机状态。

后续效率工作只沿[主计划](../plans/foundation-priorities.md#运行效率路线待实施)选择：先分清当前短窗口里的成本，再选一项；输入交接需要联动时钟/命令窗口，GPU已有compact局部输入。旧测量口径更正在BASELINE，未恢复容量矩阵或长回归。顾问客户端与原问答留本机，发现入口仍在根AGENTS；按需读其核查版，不以原答代替代码。

已交付试玩、数值HUD、固定外观迷雾记忆和忙碌点击修复，能力/操作只查FEATURES，验证只查BASELINE。试游继承普通Main，使用原领域及可选独立保存槽；没有新玩法后端。当前模型开发档仍需匹配最新版本，新开局要求查[兼容政策](../engineering/compatibility.md)。旧研究/测量在[历史](../archive/qa/README.md)，临时原件在忽略的logs；不恢复其任务。

## 受保护内容

- 保留codex/field-contest（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 原stash 424f956d280fb390d17e1f6dd879f3614b51a430原样保留。
- 退役测试WIP仍在logs/retired-test-workflow-20261111-012331/，不恢复。门仍自由穿行并保持房间，锁门后续再议。
