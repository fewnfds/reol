# 当前接续

更新：2026-11-11。整个多核优化任务仍在进行，当前goal为active。最新小段在原身体运动分区采用上，接入Godot延后完成通知，减少邮箱ready后等待主线程收取；整局吞吐仍不足。原GPU路径保留。真实收益、容量与局限只看[BASELINE](baseline.md)，阶段提交不代表整个任务完成。分支、提交和推送以Git为准。

## 接手入口

- 当前工作只维护在[主计划](../plans/foundation-priorities.md)：继续人物状态采用/空间通知/下一边界采用的阶段划分，以及显示交接尾部和可靠并发/规模；均属于此次多核任务。
- [执行设计](../specs/world-engine/execution.md)、[批执行API](../engineering/execution-batches.md)说明当前线程和交接边界；[计算范式](../engineering/settlement-contract.md#计算优化范式)、[领域频率](../engineering/simulation-pacing.md#领域频率)仍服务所有领域。
- [代码入口](../../scripts/README.md)、[owner表](../engineering/architecture/02-owners.md)定位原状态；[FEATURES](features.md)定位可玩操作。当前只支持最新存档，见[compatibility](../engineering/compatibility.md)。

## 本轮结论

最新同包复杂千人仍会降速，实际CPU执行远未吃满硬件；更高并发没有持续增益，生产默认保持4。最新测量与此前300–8192容量曲线均在BASELINE。人物Node已在模拟忙碌期间采用，但显示帧仍有滞后，旧UI/画布还在完整交接窗口读取。

本次定位到准备人物候选算向外层请求终点，却在更早的本地边界采用，导致大量候选丢弃并串行重算。现按实际内部区间准备、同一请求中继续分派，最新定位窗该类丢弃为零。整路投影和跨格时刻沿原批接口计算，原owner验证并按ID采用/通知；小批deadline复用热读取，没有另开线程平台。

本段实现先核对实际观察者只读当前身体、全部原路线输入和依赖再分区写入，通知仍有序；外部观察者自动保留逐人路径。同包千人PROJECT下降，整局差异不可靠，4000人仍明显过载。minimum=1包装大量小批反而更慢，默认恢复64。

完成通知与process共享预算，不额外准入时间；复杂千人短窗约0.89×，4/8worker接近，尚非满速/稳定60FPS。下一步处理下一边界选择/采用与有序通知。ready→collect与完整回复→下一请求分开计时，后一项含必要UI和节奏空闲。压力驱动的真实取消/新动作及社会事件、旧UI/画布同步窗口和人物显示帧年龄仍在范围内。

128身体原状态采用、300身体固定输入及同伴改写观察者对照通过。复杂fixture存读stage拒绝后，改为两个独立装配的300身体/8房间/16来源固定输入进程，完整world/motion/bodies一致，实际243个运动分区批；未宣称该fixture支持存读。实际普通移动/暂停/忙碌存读通过，完成通知短检查含预算、无新增时间及暂停许可清理。具体证据在BASELINE；报告和临时检查在忽略的logs，不恢复旧CI或长回归。

## 受保护内容

- 保留codex/field-contest（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 原stash 424f956d280fb390d17e1f6dd879f3614b51a430原样保留。
- 退役测试WIP仍在logs/retired-test-workflow-20261111-012331/，不恢复。门仍自由穿行并保持房间，锁门后续再议。
