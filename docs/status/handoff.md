# 当前接续

更新：2026-11-11。用户要求收尾、review、提交main后先停下来讨论；本轮停点goal为paused，整个多核任务未声明完成。已保留常驻协调者、共享线程池、原GPU路径、原身体运动分区采用和Godot延后完成通知。真实收益、容量与局限只看[BASELINE](baseline.md)，分支、提交和推送以Git为准。

## 接手入口

- 未完成范围只维护在[主计划](../plans/foundation-priorities.md)。当前先讨论demo试玩与后续开发，不自行恢复优化；若用户恢复，继续人物状态采用/空间通知/下一边界采用，以及显示交接尾部和可靠并发/规模。
- [执行设计](../specs/world-engine/execution.md)、[批执行API](../engineering/execution-batches.md)说明当前线程和交接边界；[计算范式](../engineering/settlement-contract.md#计算优化范式)、[领域频率](../engineering/simulation-pacing.md#领域频率)仍服务所有领域。
- [代码入口](../../scripts/README.md)、[owner表](../engineering/architecture/02-owners.md)定位原状态；[FEATURES](features.md)定位可玩操作。当前只支持最新存档，见[compatibility](../engineering/compatibility.md)。

## 当前停点

已测300–600人巡行/复杂环境短窗基本满速，复杂千人约0.89×，4000人约0.35–0.37×；不等同于全部玩法或长期60FPS。实际CPU执行远未吃满硬件，更高并发没有持续增益，生产默认保持4。人物Node已在模拟忙碌期间采用，旧UI/画布仍在完整交接窗口读取。

本轮最后追加的边界元数据分区采用已撤回：同包4000人对照没有可靠整局收益。主线只保留deadline逐人元数据/大批索引更新细分计时，以及把读取绑定切换的缓存失效从不可达return后移回setter。已运行的任务在收尾前全部结束，没有后台压测或待采用实验代码。

原身体采用、固定输入和同伴改写观察者对照通过；复杂独立装配固定输入也一致，但不支持把临时fixture当存读样本。最终相关短检查和读取切换后的原串行/多worker完整状态复核见BASELINE。临时实验脚本、原报告和导出包在忽略的logs，非主线功能，不恢复旧CI或长回归。

## 受保护内容

- 保留codex/field-contest（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 原stash 424f956d280fb390d17e1f6dd879f3614b51a430原样保留。
- 退役测试WIP仍在logs/retired-test-workflow-20261111-012331/，不恢复。门仍自由穿行并保持房间，锁门后续再议。
