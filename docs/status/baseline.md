# 构建、兼容与验证基线

核对：2026-11-08。采用版本与准确代码证据记录在此，操作范围见[FEATURES](features.md)，当前停点见[HANDOFF](handoff.md)，详细日志和限制见[QA](../qa/README.md)。历史分卷只描述当时版本。

## 通用建筑与组合空间（已推送分支）

`codex/general-buildings`最终受检代码`d00bac954b69cab096d580db002fb04013fa2543`：定义/实例/能力分开，多格/朝向、多工地/用途，独立空间事实、操作位/桌椅、原库存储藏、工作台接原生产、耐久/防护/损毁已接普通Main。13类定义、两种材料，框架出口和实际限制见[本阶段QA](../qa/20261108_building_framework.md)及[建筑合同](../engineering/construction-contract.md)。

准确代码本机4片顺序完整check **250组/126290断言/0失败**，各worker结构、导入、脚本错误/超时及退出码均通过，独立覆盖汇总核250组无遗漏；总墙钟约3282秒，最慢片约1185秒，没有放宽单片1800秒门禁。首次单进程全量因夹具/非热通知错误及1800秒超时未通过，修复与证据保留在QA。一次Sol/custom原生静态审查的3项P2/1项P3均已修复并用反例验证。

最终d00bac普通Main多格施工、座位使用、存箱三案均在完全停止游戏进程后独立恢复，checkpoint、原截止时间与整个联合未来SHA相同；RTX3060原生1280×720界面已查看。代码已推送开发分支，尚未合并main；[CI42457788038](https://github.com/fewnfds/reol/actions/runs/42457788038)完整headSha与d00bac一致，证据提交检查点为in_progress，终态待验；未以旧绿色代替。后续只整理Markdown，受检代码/数据/测试保持不变。

## 当前集成代码

用户授权后，main已从`b3ae3399d24e01975d231cd000c0af342740070b`快进并推送到`2e6b6a61caf11b5560c15a97f1a58cb156a7300b`，包含前阶段共同空间与最小行动，以及此前稀疏执行和测试工具。[CI42375335176](https://github.com/fewnfds/reol/actions/runs/42375335176)已核完整headSha2e6b6a6一致、completed/success。主线合并在新建筑开发之前完成，保护WIP/stash未改。

前阶段共同空间最终代码`f50f0a84085294faf72e6315e99aa5343e7dbf15`的249组/125102断言/0失败、一次Sol/custom审查及两案完全停开证据见[阶段QA](../qa/20261107_world_space_actions.md)。该能力现已在main；旧QA的“未合并/远端待验”只记录当时状态，不能覆盖本页。

## 术语与运行入口

受检代码`771a587d20a38998845331fb214cd886d361d876`：普通环境成员和调度domain统一为`RegionalSimulation.environment_fields`；区域存档键`local_heat`通过codec映射，现行schema不变。术语/真实代码映射见[唯一入口](../engineering/terminology.md)。本包import与定向10组1203断言通过，RTX3060真实HUD确认灵气文案，一次Sol/custom静态审查无发现；完整CI尚待准确SHA，证据见[QA](../qa/20261107_terminology.md)。该整理不新增游戏机制或改变main集成范围。

## 测试工作流与成本

测试提交`f166cdb4360e91055a3f942cedf66ae446f2301e`与受检快照`2b9828040343e53a469ec8cdce5f12df16656e31`的完整tree一致：4片完整覆盖本机**248组/124981断言/0失败**，各worker日志/退出码与汇总校验通过，Python72项及错误退出smoke通过，一次Sol/custom静态审查无可执行发现。组内合计1495.275→1325.163秒；受改两组重复装配合计减少40.751秒，其余波动不全归因代码。4片最慢组内466.318秒，本机顺序验证不等于GitHub并行实测；一个未改组的预算循环断言次数波动已定位，固定检查/结果出口没有减少。范围、完整证据与远端待验见[优化QA](../qa/20261107_test_optimization.md)。生产代码及存档格式未改。

前序受检代码`b60adadfcab73a17e101b62538da62ddc5bccf9f`建立248组精确选组和逐组计时；当时Python60项及有界五组54894断言通过。其后纯文档提交`d27337d67c0148132dfaef2d802d72a860b62d38`的[CI42356120868](https://github.com/fewnfds/reol/actions/runs/42356120868)已在本轮真实提交检查点核completed/success，完整SHA相符；不替代后续术语和分片版本的远端结果。五组实测与限制见[成本调查](../qa/20261107_test_cost_audit.md)。

## 顶层稀疏执行框架（已集成）

代码`ee3504d3c313aa07ac4e87caec3bd39488c725e3`在`codex/sparse-world-execution`建立通用owner-local能力参与/活跃/到期/变脏索引，普通环境与健康接入。准确代码本机完整check **248组/124980断言/0失败**，一次Sol/custom静态审查无有效发现；普通两次来源操作短样本224/221ms→8.081/7.173ms，无GPU。存档字段/版本不变、恢复重建派生索引；未把其他旧域自动迁入，不代表满密度或16GB整机验收。

本轮真实文档提交检查点核得[CI42345202281](https://github.com/fewnfds/reol/actions/runs/42345202281)，完整headSha`2f305de8efcbd8e51c290bbeae73cc5531fc2996`一致，终态**failure：测试1800秒超时（test=124）**。该head与上述本机受检代码只有文档差异；Python工具测试和导入完成，但Godot没有完整终态汇总，不能称远端通过。末条RUN为`test_terrain_edits`，不足以证明超时根因。未重跑/轮询或放宽门禁；日志与限制见[QA](../qa/20261107_sparse_execution.md)。

## 普通环境接管基线（已验收并入main）

最终代码 `6137481a07ec98b372e32ca857e546f1e1b07ee1` 已使普通Main接唯一室外冷热/五行场，原物与材料变更、人体/野药温度、共同时间及普通存档共用当前模型。保存拒绝未完成事务；旧根1–51明确拒绝，原档保留。准确SHA本机完整check **244组/124778断言/0失败**，1174源文件前后不变；同SHA双进程普通Main存读同未来、RTX3060真实画面与600帧联合负载通过。一次Sol/custom静态审查的3项有效发现均修复。普通单次生成/材料变更仍约0.22秒卡顿；不代表满密度或16GB整机验收。最终[CI42337874837](https://github.com/fewnfds/reol/actions/runs/42337874837)在后续真实调查文档提交检查点已核completed/success，完整headSha6137481一致；本包本机与CI均有准确代码证据，不重复测试。集成点`ffe7e8c705d2d7259dfb77dcfba3dd0a64c9c61c`已并入并推送main，之后仅更新文档；停止点查[HANDOFF](handoff.md)，完整证据与局限见[QA](../qa/20261107_world_engine_finish.md)。

## 采用版本与存档

- Godot **4.7.2 stable** 是这次采用和验证的版本；长期跟进最新稳定版，每次升级需核插件、CI与导出模板。当前是 GDScript、Windows 本机开发，CI 为 Linux headless；Windows 正式独立包未验收。
- 当前普通联合根存档 schema **53**，区域 **44**、村落 **7**、场状态 **4**（`outdoor_fields_v1`）、环境受体状态 **3**（climate **2**）、器物状态 **8**。内容包 **v2** 固定包含39份定义/开局及来源digest；部分动作等规则仍直接读取项目文件。当前只接受根53；旧根52因建筑模型、1–51因环境模型明确拒绝；[兼容政策](../engineering/compatibility.md)不承诺永久迁入链，真实fixture保持只读。
- 本轮起点 `2483a3771bc9f469509293a514fb0a059eefe095`。原环境缓存、温度及两测试的四WIP已备份并与原工作区字节核对，不混入隔离实现/验收。分支快照见[分支状态](branches.md)，当前操作以HANDOFF为准。

## 历史里程碑入口

当前验收只看上面的主线/分支版本；以下QA保留各自当时的范围、失败、性能与CI，不能把其中“未接Main、pending、下一包”当作当前状态。

| 历史主题 | 证据入口 |
|---|---|
| 世界骨架、空间查询、生命周期、联合出口 | [对象](../qa/20261105_world_object_contract.md)、[生命周期](../qa/20261105_object_lifecycle.md)、[第一阶段出口](../qa/20261105_world_foundation_exit.md) |
| 环境来源、基础缓存与独立GPU | [来源](../qa/20261105_environment_source_bindings.md)、[缓存](../qa/20261105_environment_ground_cache.md)、[计算](../qa/20261105_environment_ground_compute.md) |
| 连续响应、密集负载及有限优化 | [响应](../qa/20261105_environment_response.md)、[优化](../qa/20261106_environment_optimization.md)、[冷建](../qa/20261106_environment_cold_build.md)、[性能接续](../qa/20261107_world_performance_followup.md) |
| 普通接入与环境主线收尾 | [运行接入](../qa/20261107_framework_runtime_integration.md)、[最终主线验收](../qa/20261107_world_engine_finish.md) |
| 本轮顶层稀疏执行 | [框架验收与普通入口成本](../qa/20261107_sparse_execution.md) |

旧完整基线流水可从Git的`2f305de`版本文档追溯；不在当前入口复制历史全文。早期分卷仍在[baseline-history](../qa/baseline-history/README.md)。当前技术缺口集中在[技术落地总表](technical-status.md)。
