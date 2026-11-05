# 当前接续

核对：2026-11-05。第一阶段A–E和第二阶段A1已完成声明范围验收。本轮用户只要求下一小阶段计划，未授权本轮改游戏代码；不自动接A2/B或恢复旧Goal。当前无Goal。

最新一轮用户只要求下一小阶段计划。已写[A2a分块基础目标缓存候选](../plans/environment-object-loop/cache.md)：统一通道/舍入，复用packed缓存接真实原物及可靠失效，量测装配/冷建/热读/局部重算；仍不含实际响应、联合原物事务或Main接管。当前只交付方案，未改游戏代码、未启动引擎或创建Goal，等待讨论后再按明确授权实施。

随后讨论补充：真实手持搬运须按原人物路径/共同时间处理沿途暴露，慢走/快跑/停留产生不同升温与尾迹。尾迹是地块实际状态，不复制静态来源。现耗时move要求人物原位等待、到期一次转移，尚无真实搬运路线；A1无携物来源/A2a无实际响应，均不能宣称已实现。已补[连续性候选](../plans/environment-object-loop/continuity.md#真实搬运与运动来源)及联合验收；仍在讨论，不扩大为本轮代码实施，携物整体遮掩未定。

## 已完成包与停点

A1代码已提交并推送 `8bf7aa2a012af393fbc1b96fea6220aa18825833`：显式schema/digest、真实ground实物和材料堆来源投影、有界局部五行max/冷热等级合成。原位置/数量仍唯一归原owner，查询不推进时间。接口见[来源查询合同](../engineering/environment-source-query-contract.md)，证据见[来源QA](../qa/20261105_environment_source_bindings.md)。定向147断言/0失败，真实64²至512²密度基准通过；原生Sol/custom只读审查无可行动问题；精确SHA独立检出完整check通过：255组、98618断言、0失败，1094.512秒，无ERROR/SCRIPT ERROR。

独立验证检出已在保存完整日志后移除；主代理统一验证，没有混四份保护WIP。日志在 `logs/environment_a1/`，含 `isolated-check-result.json` 和 `isolated-logs/`。本包已完成声明范围，当前停下向用户报告；没有活动测试或审查进程。

普通Main旧Q不变，未接实际温度/五行残留、来源缓存或原物联合prepare/commit事务；新定义未加入普通内容包/写档schema。配置绑定plain_slate/stone_slab及普通材料可复用profile，不为温石扩玩法。A1不是每帧全格查询方案；512²满格局部查询约10ms p99，持续批量场更新须后续单包验收。本包完成后只报告，A2/B依[候选方案](../plans/environment-object-loop/README.md)再讨论排定。

冷热沿用户确认的单项signed thermal_grade（正热负冷），两侧max是合成临时极值。巨型通行/单格/AOE仅[调研](../../design/research/unit_footprint_and_clearance.md)，本包未重写导航或战斗。

## 已完成与证据

A多类对象/能力查询与显式集合空间快照，B受控实物与多格地面位置，C同账本材料堆拆及共同耗时搬运，D装配/候选存读与在途恢复，E开发诊断/普通呈现/声明规模测量均已接入。身体、器物和数量继续沿原所有者，接口是权威开发接缝，不授玩家距离/认知/社交权限。

- [生命周期合同](../engineering/object-lifecycle-contract.md)说明请求、归属、占地、时间、取消和恢复边界。
- [最终出口QA](../qa/20261105_world_foundation_exit.md)记录同一普通Main离返后完全退出、新进程恢复和相同未来；512²真实物品落盘、批量搬运与候选；满格呈现1800帧；1/4/8大型身体及保存候选。
- [完整包QA](../qa/20261105_object_lifecycle.md)保留原失败、修复、审查与早期测量，不覆盖原日志。

游戏主代码 `c529c96910a0ef07af5e6d720bd848f395c4fed8`，一次原生Sol/custom只读审查的五项问题已修复到 `b78f3af607c3b8c798411f4945de123d1d0ebf30`。后者精确SHA在独立检出完整check通过：254组、98467断言、0失败、无ERROR/SCRIPT ERROR，1127.369秒。后续只扩四个验收基准和文档，游戏逻辑/定义/场景未变。最终基准逐次记录HEAD、diff和脚本哈希；无额外整包审查或完整回归。

## 工作区保护与版本

分支 `codex/world-engine`；游戏、验收脚本与文档按可解释提交保存。最后推送和本地HEAD以Git为准。环境首轮纯文档提交检查点一次查到06067d300a6c0158a1f602458afca2ac80a68598对应CI41994818299 completed/success，SHA匹配；前次概念修正文档提交点31850b7f0a6883475c96259db651f637ae96d3a0无匹配run；本次真实代码提交前一次查afd5459ebd7f18a8e427fe0c96183ad5d0c125bb也无匹配run。A1末次文档提交时CI42008084331仍in_progress；本次方案的真实文档提交检查点，通过tools/ci.py核为completed/success，完整headSha匹配8bf7aa2a012af393fbc1b96fea6220aa18825833。本机同SHA完整check亦已通过。不轮询，新推送不立即查询或等待。主验收另有上述精确游戏SHA的本机完整check，不包含本机四份WIP。

四份原环境WIP不属于本包、未混入提交或精确SHA回归；起始SHA256在 `logs/world_lifecycle/protected.json`，须继续原样保护：

- `scripts/sim/environment_field_cache.gd`
- `scripts/sim/environment_temperature_state.gd`
- `tests/sim/test_environment_field_cache.gd`
- `tests/sim/test_environment_temperature_state.gd`

原始性能/截图/审查/失败日志均在忽略目录 `logs/world_lifecycle/`。独立check原日志保留到 `isolated-check-logs/`；最终检出日志/存档另保存到 `final-validation-artifacts/` 后可移除自建验证worktree。不可删用户文件或四处WIP。

## 已知限制与后续依赖

普通Main冷热仍是旧Q，A1仅查询接缝；A2/B候选后续再排。普通Main接管、GPU、完整房温、生态及大量自主NPC属于[后续基础依赖](../plans/foundation-priorities.md)。用户要求每次1–2项后讨论，不自动连续扩阶段。动态只测原大型身体上限8；环境传播不由静态物品密度证明。

满密度候选恢复约32.7秒、工作集峰4.82GiB；大量JSON和恢复延迟、历史槽位/回执安全回收仍有优化空间。真实16GB主机、满密度Main跨进程存档、全AI与新场同时运行、正式切片和独立发布未验。不把第一阶段底座完成称为完整游戏完成。
