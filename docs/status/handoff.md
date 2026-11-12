# 当前接续

更新：2026-11-12。用户授权的最后一轮全面性能优化已收尾：官方性能目录及全部子篇已核对，主要改动完成review、短反例及实际CPU/GPU核查，最终release已重建并验证。代码和文档交付main，实际提交以Git为准。此阶段结束后先由用户试玩/讨论，不自动恢复旧容量攻坚或研究待办。

## 接手入口

- [功能试游](../engineering/tooling/usage.md#功能试游)说明启动、独立保存槽和Windows试玩包；体验步骤只在游戏内维护。普通Main与导览共用原领域，没有第二套玩法后端。
- [主计划](../plans/foundation-priorities.md)维护最终采用/撤回/暂缓和后续功能候选；[BASELINE](baseline.md)维护真实负载、最终性能、review范围及已知容量限制；[FEATURES](features.md)维护已可玩操作。
- [计算接入](../engineering/execution-batches.md)是直接领域逻辑、事件/分频、CPU批与GPU场的唯一选择指南，按需使用，不要求所有功能实现统一接口。领域接口查[工程地图](../engineering/README.md)。
- [代码入口](../../scripts/README.md)与[owner表](../engineering/architecture/02-owners.md)定位原状态；[官方逐篇研究](../../design/research/large_simulation_optimization.md#官方性能指南逐篇核查2026-11-12)定位来源与适用性，不是一份新任务队列。

## 当前事实与边界

同刻来源合并、GPU缓冲/绑定复用、变化驱动衣着外观、连续列身体边界结果、空人物回调停用及物品位置读取减量均已实现；无收益的目击者索引和协调者全衣着构建实验已撤回。算法、采用条件和设备生命周期只在原工程页解释；最终包、测量及失败/未测范围只在BASELINE记录。

CPU批、协调线程和专用GPU来源场实际在用，但准备/采用、直接因果owner和主线程呈现仍限制扩展。千人复杂场景尚未满速，也未达到稳定60FPS；不把短窗、低总CPU占用或局部GPU收益当作全玩法承诺。共同时间、活动数量与既有来源采样频率未改。

世界事实、模型响应、采样精度与调度延迟的唯一概念正文在[运行与精度](../engineering/simulation-pacing.md#世界事实与计算精度)。当前仍按完整共同边界推进，未实现慢环境跨步采用或任意业务低优先级池；新产品取舍不等于已有异步实现。不要求长期全局同未来，也不为去确定性删除便宜的稳定ID/量化/随机状态。

下一项候选是主计划中的输入、选择与指令闭环；右键移动、A/S/H仍未启用，不从归档恢复旧操作要求。当前试玩继续使用FEATURES中的键位、数值HUD和固定外观迷雾记忆。存读只支持[最新开发格式](../engineering/compatibility.md)，不恢复旧档迁移层。

顾问原问题、回答、逐项核查及官方全文缓存留在忽略的`.local/advisor/`，入口见根AGENTS，用法与参数只查其本机README。凭据/程序不入库，回答不能代替源码和实测。临时callback/owner剖析已按原bytes/SHA恢复；本轮没有保留探针源码。原包和日志在忽略的logs，旧研究见[历史](../archive/qa/README.md)。

## 受保护内容

- 保留codex/field-contest（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 原stash 424f956d280fb390d17e1f6dd879f3614b51a430原样保留。
- 退役测试WIP仍在logs/retired-test-workflow-20261111-012331/，不恢复。门仍自由穿行并保持房间，锁门后续再议。
