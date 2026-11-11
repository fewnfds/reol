# 当前接续

更新：2026-11-11。本轮完成计算接入、代码职责与项目记忆整理，收尾提交main。当前没有active或paused goal，不恢复旧容量攻坚；后续开发范围等待下一次讨论。分支、提交和推送状态以Git为准。

## 接手入口

- [主计划](../plans/foundation-priorities.md)维护本轮交付和暂缓范围；[BASELINE](baseline.md)维护版本、实测与已知限制。
- [计算接入](../engineering/execution-batches.md)是直接领域逻辑、事件/分频、CPU批与GPU场的唯一选择指南，按需使用，不要求所有功能实现统一接口。具体领域只查[工程地图](../engineering/README.md)。
- [代码入口](../../scripts/README.md)、[owner表](../engineering/architecture/02-owners.md)定位原状态；[FEATURES](features.md)定位可玩操作。当前只支持最新存档，见[compatibility](../engineering/compatibility.md)。

## 本轮接续

人物需求读取已从运动读取拆开，自定义需求回调只撤销需求借读；原顺序执行与运动候选复核保留。共用CPU默认并发集中到SimBatchExecution.DEFAULT_WORKERS，工具省略参数时沿用游戏值。

重复的执行候选规格已删除，旧多核长记录与研究调用链移到[历史](../archive/qa/README.md)，当前入口不再指向旧任务。参数定义、工具语法和测量分别归代码、usage和BASELINE；没有增加AGENTS约束。

短检查、原生/自定义需求的完整状态对照、普通会话存读和单次真实千人窗口已结束，证据见BASELINE；没有后台压测或待采用实验。临时脚本、报告及构建在忽略的logs中。

## 受保护内容

- 保留codex/field-contest（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 原stash 424f956d280fb390d17e1f6dd879f3614b51a430原样保留。
- 退役测试WIP仍在logs/retired-test-workflow-20261111-012331/，不恢复。门仍自由穿行并保持房间，锁门后续再议。
