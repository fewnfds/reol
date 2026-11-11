# 当前接续

更新：2026-11-11。整个多核优化任务仍在进行，当前goal为active。线程底座、人物热表与需求分区、独立人物Node发布已有；最新小段修正内部时间区间错配，并补整路/跨格候选和小批热读取。原GPU路径保留。真实收益、容量与局限只看[BASELINE](baseline.md)，阶段提交不代表整个任务完成。分支、提交和推送以Git为准。

## 接手入口

- 当前工作只维护在[主计划](../plans/foundation-priorities.md)：继续人物状态采用/空间通知/下一边界采用的阶段划分，以及显示交接尾部和可靠并发/规模；均属于此次多核任务。
- [执行设计](../specs/world-engine/execution.md)、[批执行API](../engineering/execution-batches.md)说明当前线程和交接边界；[计算范式](../engineering/settlement-contract.md#计算优化范式)、[领域频率](../engineering/simulation-pacing.md#领域频率)仍服务所有领域。
- [代码入口](../../scripts/README.md)、[owner表](../engineering/architecture/02-owners.md)定位原状态；[FEATURES](features.md)定位可玩操作。当前只支持最新存档，见[compatibility](../engineering/compatibility.md)。

## 本轮结论

最新同包复杂千人仍会降速，实际CPU执行远未吃满硬件；更高并发没有持续增益，生产默认保持4。最新测量与此前300–8192容量曲线均在BASELINE。人物Node已在模拟忙碌期间采用，但显示帧仍有滞后，旧UI/画布还在完整交接窗口读取。

本次定位到准备人物候选算向外层请求终点，却在更早的本地边界采用，导致大量候选丢弃并串行重算。现按实际内部区间准备、同一请求中继续分派，最新定位窗该类丢弃为零。整路投影和跨格时刻沿原批接口计算，原owner验证并按ID采用/通知；小批deadline复用热读取，没有另开线程平台。

下一步先量清有序投影/通知的原状态读写：哪些计算可以继续借读并行，哪些回调会改变后续身体。当前PROJECT仍重，不能把不同人物的位置提前一起发布而默认观察语义不变。压力驱动中的真实取消/新动作及社会事件也有较大成本，须与常规模拟区分；不预设普通寻路或GPU是最大项。此前衣物全扫描已沿原持有索引消除。

最新300原身体/80次固定输入的旧回调与新借读/自动worker完整世界、移动及发布一致通过；短actor_batch补了整路/路段、顶点、零距离段、跨格时刻与旧候选拒绝。此前干湿/休息等输入、独立显示隔离、实际移动/暂停/忙碌存读已验证。具体证据在BASELINE；原报告和临时检查位于忽略的logs，不恢复旧CI或长回归。

## 受保护内容

- 保留codex/field-contest（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 原stash 424f956d280fb390d17e1f6dd879f3614b51a430原样保留。
- 退役测试WIP仍在logs/retired-test-workflow-20261111-012331/，不恢复。门仍自由穿行并保持房间，锁门后续再议。
