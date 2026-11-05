# 当前接续

核对：2026-11-05。第一阶段A–E和第二阶段A1已完成声明范围验收。用户已授权创建Goal并完成第二阶段A2a分块基础目标缓存；Goal已active。本包完成后报告讨论，不自动扩实际响应、移动携源或房间。

**空间选型：** 采用方格地形/建造＋原人物权威子格位置＋按格缓存环境。人物无需停格心，移动途中位置继续参与规则；未来移动来源首版从权威位置派生所在格发源，跨格游戏时刻切换，按驻留时间接续环境建立/消散。这是可调整的工程选型，不恢复“全对象格位置权威”的固定结论。依据见[空间调研](../../design/research/spatial_models.md)，细节见[调度方案](../plans/environment-object-loop/scheduling.md)。当前不改身体空间模型，四份保护WIP原样保留。

**A2a进行中：** 新`environment_ground_cache.gd`已接原物投影、16×16块缓存、有界装配/续算及生命周期通知前失效；库存ground epoch和器物bulk generation用于拒绝旁路变化/同实例恢复。算术/epoch定向1404断言通过，真实64²/128²密度初测通过；综合缓存测试、更大密度、一次代码审查和精确版本完整回归尚待完成，不把初测当作包验收。日志位于`logs/environment_a2/`及`logs/benchmarks/environment_ground_cache_*`。

**性能入口：** 用户确认仍沿PC、16GB整机RAM、单RTX3060目标；唯一规格入口为[全项目性能基线](../engineering/architecture.md#全项目性能基线)，AGENTS和docs索引已直接链接。游戏约10GB是可接受量级而非另立整机约束。256MiB是开发者在A2a页自行提出的模块警戒，非skill/用户规则，已撤销；不再据此扩优化任务。GPU已允许，端到端收益与实际接入分别验证。

第二阶段目标是环境与组合空间。下一排定小包为[A2a分块基础目标缓存](../plans/environment-object-loop/cache.md)，只接A1地面静物：统一通道/舍入、真实来源装配、分块缓存及可靠局部失效，并测密度性能。完成一包后报告讨论；实际响应、原物联合事务、移动携源及Main接管另排，不因空间选型自动连做。

## 讨论确认与实施缺口

- 方格地形、多格实体一份状态仍有效；全对象强制落格/停格心和格间位置纯视觉已撤回。环境读原模拟位置，不能从画面插值反推。见[空间规则](../../design/rules/objects-and-interaction.md)。
- 场建立/消散沿共同整数游戏毫秒。移动场首版选整格发源近似，后续动态包验证跨格误差、驻留时长及密集移动性能，再决定是否需要子格采样。当前A2a不实施移动场，A1静物偶数多格发源向左上约定保留。
- 真实搬运会因驻留时长形成不同沿途实际场状态，尾迹不复制来源。现耗时move要求人物原地等待、到期转移；A1不接携物，响应原型未接动态来源。携物整体中和/遮掩仍未定。见[连续性](../plans/environment-object-loop/continuity.md)。
- 当前 `SimLocalMotion.position` / `SimRouteTravel.project` 的连续位置是原身体真值，参与碰撞/行动；不因未定候选把它当作应立即改正的错误。后续空间变更须核对导航、中断、在途存读与战斗消费者，本轮不重写。
- 当前普通时钟50ms/步、80步/帧，区域事件预算4096不是硬毫秒预算。欠算保留，但持续过载缺实用背压上限，输入无时间戳历史。新场没有真实刷新率/低配尾迹验收；接管前须补有限追赶/受控降速与输入边界。见[调度候选](../plans/environment-object-loop/scheduling.md)。

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
