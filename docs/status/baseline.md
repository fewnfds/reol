# 构建、兼容与验证基线

## 通用建筑与组合空间（分支验收中）

`codex/general-buildings`从已合入main的`2e6b6a6`继续。通用定义/多格/朝向、多处工地/用途、操作位、真实储藏/工作台与耐久/损毁已接普通入口；定向结果和独立进程证据归[本阶段QA](../qa/20261108_building_framework.md)，完整check及本包原生审查尚待最终版本记录。旧阶段的绿色结果不冒充新包验收。


核对：2026-11-07。这里记录采用版本与对应范围的证据；实际可操作内容见[功能入口](features.md)，任务状态和未提交工作见[接续](handoff.md)。旧的逐包原文已完整拆入[历史分卷](../qa/baseline-history/README.md)，具体测试和画面见[QA索引](../qa/README.md)。

## 当前集成代码

main已包含`f166cdb4360e91055a3f942cedf66ae446f2301e`的代码与后续纯文档整理，稀疏执行、术语入口及测试分片共用当前运行模型。该提交与下述已验/已审查快照的完整tree相同；没有因整理再次修改游戏代码或重复完整测试。起点main `b3ae3399d24e01975d231cd000c0af342740070b`的CI42365643089已在真实文档提交检查点核completed/success；本阶段新代码另行验收。[集成记录](../qa/20261107_mainline_cleanup.md)说明验证对应关系和隔离工作。

## 当前阶段分支

`codex/world-space-actions`实现[共同空间与最小行动](../qa/20261107_world_space_actions.md)：现有身体/地面物/结构的实时局部查询、提交变化和恢复失效，取放/施工共用最小行动接缝。最终受检`f50f0a84085294faf72e6315e99aa5343e7dbf15`本机完整check **249组/125102断言/0失败**，结构、导入、脚本错误门禁及退出码通过，约1286秒。一次原生Sol/custom静态审查的3项P2已修复；普通Main两份在途档完全停开后checkpoint/完整未来一致。后续仅更新Markdown并推送阶段分支，远端CI结果待下次真实提交检查点核验。原存档版本不变；该分支能力尚未合入main。

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
