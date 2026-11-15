# 已确认的未修问题

核查日期：2026-11-15。以下六类问题均已结合当前源码和本机隔离探针复现，尚未修复。它们有各自的触发条件；检查通过或本页未列出的问题，不代表其他组合已经验收。本轮已修项与整体验证见[构建基线](baseline.md)。

## 1. 防御反应继承攻击技能身份

`damaged`、`blocked`、`shield_broken` 反应将来源切换为防御者时，仅重取阵营与攻击属性，仍保留进攻事件的 `action`、`activation`。如果防御者的反应附加状态，该状态会读取攻击技能的反应规则，发生错误归因或意外传播。

实测组合：防御者自定义 `damaged -> bundle -> plague` 状态，受到 `plague_needle` 攻击后，新状态的 `source=2`，却保存 `ability=plague_needle`、进攻方的 `activation=123` 及 `plague_spread`。现有默认防御被动不是这条状态组合，不能说所有反击都会触发传播。

源码：[事件翻转](../../scripts/sim/kernel/combat_reactions.gd#L44)、[反应效果提交](../../scripts/sim/kernel/combat_reactions.gd#L162)、[状态保存规则](../../scripts/sim/kernel/combat_effects.gd#L43)。后续修复应区分触发原因与新效果来源，保留共享因果预算。

## 2. 命中提前开放取消窗口时丢失技能缓冲

技能在当前动作期间合法进入缓冲，但命中使取消窗口提前开放，而该技能尚未结束冷却时，`prepare()` 先删除缓冲，再收到 `request()` 的 `cooldown` 拒绝，导致这次输入丢失。

实测使用现有铁剑动作：`slash_1` 开始后 60 ms 缓冲 `cleave`，其冷却到 180 ms、缓冲也到 180 ms；平砍真实命中，将技能取消点提前到 160 ms。170 ms 时缓冲已消失，210 ms 仍未启动 `cleave`。目标实际扣除 35 HP，无需手工设置命中确认。需要满足冷却结束、缓冲期限和命中取消点的相对顺序，普通无冷却输入不受此条件影响。

源码：[缓冲准入](../../scripts/sim/kernel/combat.gd#L145)、[缓冲执行](../../scripts/sim/kernel/combat.gd#L300)、[时间边界](../../scripts/sim/kernel/combat.gd#L260)。修复需同时核对冷却到期边界和缓冲超时处理。

## 3. 返航器物撞墙预计算绕过较早的主人死亡

`collect()` 预计算一段移动时，若返航器物将在该段后面撞墙，会立即将其最终 `phase` 改为 `dropped`。随后结算这段内较早发生的主人死亡时，`drop_owner()` 跳过了已经标为 `dropped` 的器物，未记录停止时刻，也未回退到死亡时的位置；较晚收集的命中可通过停止时间检查。

隔离实测 `collect(0,100)`：收集到 23 ms 命中，器物随后撞墙并预先成为 `dropped`；按 5 ms 调用主人掉落处理后，`stopped_ms` 仍缺失、20 ms 仍被判为活动。该探针验证收集与提交顺序，100 ms 是探针区间，不是当前正常帧长或游戏性能结论。触发条件是同一收集区间内先死亡、后返航撞墙；普通飞行、已在前一区间落地的器物不是此问题。

源码：[主人死亡处理](../../scripts/sim/kernel/implements.gd#L86)、[返航撞墙](../../scripts/sim/kernel/implements.gd#L111)、[命中停止检查](../../scripts/sim/kernel/combat.gd#L588)。修复需让区间末态与按事件时刻查询的活动状态一致。

## 4. 状态眩晕期限混入其他来源，提前移除后聚合未回算

新眩晕状态把 `combat.damage()` 返回的总剩余眩晕时间当作自身期限。实测先施加 300 ms 长眩晕，10 ms 时另一来源施加 50 ms 短眩晕，短实例也被保存为到 300 ms；20 ms 驱散长实例后仍晕到 300 ms。短实例的独立期限应为 60 ms，再由存活来源聚合实际控制时间。

此外，移除眩晕时仅 `dispelled` 原因重算 `stun_until`。实测 30 ms 以 `source_removed` 移除最后的状态，状态表已空但 `stun_until=300`。默认近战命中的受击硬直不是这里测试的 `status.kind=stun`；当前目录没有现成的该类状态范例，问题在可复用状态能力及其扩展组合中。

源码：[眩晕状态期限](../../scripts/sim/kernel/combat_effects.gd#L72)、[移除聚合](../../scripts/sim/kernel/combat_effects.gd#L94)、[总控制期限计算](../../scripts/sim/kernel/combat.gd#L702)。修复应保留控制预算和普通受击硬直，分别维护来源期限及有效总期限。

## 5. 光环状态驱散后，持续留在范围内不再获得该贡献

移除状态会从光环成员的 ID 数组中删除它，但保留成员键。光环后续只给没有成员键的角色挂状态，因此状态驱散后在范围内等待也不会重挂；多个贡献仅移除一项时同样没有缺项补全。

实测现有 `radiant_totem`：获得 3 护甲后，通过通用驱散效果移除；继续留在范围内推进两个周期，护甲仍为 0，成员记录为 `{1: []}`。当前没有默认主动驱散技能，探针调用已实现的驱散能力；未被移除的普通光环不会自行失效。持续光环的驱散后重挂时机需在修复时明确，不能把本次异常当成已定的永久免疫规则。

源码：[删除成员状态引用](../../scripts/sim/kernel/combat_entities.gd#L86)、[成员准入](../../scripts/sim/kernel/combat_entities.gd#L110)、[状态移除通知](../../scripts/sim/kernel/combat_effects.gd#L94)。

## 6. 自治生活持续重选没有可用作业位置的近目标

生活决策按目标得分选出一个候选，失败后只有全局短暂等待，没有对该失败目标的暂时避让或备选选择。近目标持续没有可达作业位置时，角色可能反复选择它，闲置可用的稍远目标。

实测角色携带 1 木材，已知近箱四周封闭、远箱可达。推进 6 秒仍在原地，两箱均未收到木材；近箱失败后的线索刷新到 5856 ms，远箱仍是 0 ms。随后手动指定远箱，实际成功存入 1 木材。本例在作业位置筛选就失败，没有产生 `path_failed`；不能据此宣称每次重试都做了完整 A*。

源码：[候选评分与选择](../../scripts/sim/kernel/livelihood.gd#L92)、[失败后的再次唤醒](../../scripts/sim/kernel/livelihood.gd#L207)。修复应利用角色已知信息和真实失败反馈，避免为备选搜索读取全局隐藏状态。

## 本机复现证据

探针与日志均为本机工作文件，不入库；以下路径供同机接续定位，代码结论与触发条件已在正文保留。

| 范围 | 隔离探针 | 最新完整退出日志 |
|---|---|---|
| 问题 1–5 | `.local/review-20261115/backlog_combat.gd` | `logs/backlog-combat-20261115-232148-164792800.log` |
| 问题 6 | `.local/review-20261115/backlog_life.gd` | `logs/backlog-life-20261115-232110-537273800.log` |

Godot 4.7.2 headless，探针输出观察值而非要求已知缺陷通过断言；退出码 0 表示探针完整执行，不表示上述问题已修复。未将这些规则探针当作 GUI、性能或主观手感验收。

## 已排除的顾问误报

- “读取不存在的 `old.max_stacks`”：当前对应判断实际读取 `spec.max_stacks`，见[状态添加](../../scripts/sim/kernel/combat_effects.gd#L43)。
- “恢复环境数组未分配、未重建索引”：恢复路径已 `resize` 相关数组、重建静态数据并 `index_mobile`，见[恢复过程](../../scripts/sim/kernel/persistence.gd#L76)。
- “正常 `build` 入口未刷新拓扑，随后必定穿墙”：正常 Runner 命令批处理后、模拟前已刷新，见[命令边界](../../scripts/sim/kernel/runner.gd#L338)；不能仅看 `World._command` 一个分支下结论。
- “移除角色时 `effects.remove_target()` 必然遗留光环成员引用”：角色移除/死亡实际先调用 `entities.forget_member()` 再删除状态，见[死亡路径](../../scripts/sim/kernel/world.gd#L556)及[移除路径](../../scripts/sim/kernel/world.gd#L1241)。这条顾问推断不成立；与问题 5 的驱散后重挂缺失是不同路径。
