# 构建、兼容与验证基线

核对：2026-11-07。这里记录采用版本与对应范围的证据；实际可操作内容见[功能入口](features.md)，任务状态和未提交工作见[接续](handoff.md)。旧的逐包原文已完整拆入[历史分卷](../qa/baseline-history/README.md)，具体测试和画面见[QA索引](../qa/README.md)。

## 顶层稀疏执行框架（分支验收）

代码`ee3504d3c313aa07ac4e87caec3bd39488c725e3`在`codex/sparse-world-execution`建立通用owner-local能力参与/活跃/到期/变脏索引，普通环境与健康接入。准确代码本机完整check **248组/124980断言/0失败**，一次Sol/custom静态审查无有效发现；普通两次来源操作短样本224/221ms→8.081/7.173ms，无GPU。存档字段/版本不变、恢复重建派生索引；未把其他旧域自动迁入，不代表满密度或16GB整机验收。

本轮真实文档提交检查点核得[CI42345202281](https://github.com/fewnfds/reol/actions/runs/42345202281)，完整headSha`2f305de8efcbd8e51c290bbeae73cc5531fc2996`一致，终态**failure：测试1800秒超时（test=124）**。该head与上述本机受检代码只有文档差异；Python工具测试和导入完成，但Godot没有完整终态汇总，不能称远端通过。末条RUN为`test_terrain_edits`，不足以证明超时根因。未重跑/轮询或放宽门禁；日志与限制见[QA](../qa/20261107_sparse_execution.md)。

## 普通环境接管基线（已验收并入main）

最终代码 `6137481a07ec98b372e32ca857e546f1e1b07ee1` 已使普通Main接唯一室外冷热/五行场，原物与材料变更、人体/野药温度、共同时间及普通存档共用当前模型。保存拒绝未完成事务；旧根1–51明确拒绝，原档保留。准确SHA本机完整check **244组/124778断言/0失败**，1174源文件前后不变；同SHA双进程普通Main存读同未来、RTX3060真实画面与600帧联合负载通过。一次Sol/custom静态审查的3项有效发现均修复。普通单次生成/材料变更仍约0.22秒卡顿；不代表满密度或16GB整机验收。最终[CI42337874837](https://github.com/fewnfds/reol/actions/runs/42337874837)在后续真实调查文档提交检查点已核completed/success，完整headSha6137481一致；本包本机与CI均有准确代码证据，不重复测试。集成点`ffe7e8c705d2d7259dfb77dcfba3dd0a64c9c61c`已并入并推送main，之后仅更新文档；停止点查[HANDOFF](handoff.md)，完整证据与局限见[QA](../qa/20261107_world_engine_finish.md)。

## 采用版本与存档

- Godot **4.7.2 stable** 是这次采用和验证的版本；长期跟进最新稳定版，每次升级需核插件、CI与导出模板。当前是 GDScript、Windows 本机开发，CI 为 Linux 无头；Windows 正式独立包未验收。
- 当前普通联合根存档 schema **52**，区域 **43**、村落 **7**、场状态 **4**（`outdoor_fields_v1`）、环境受体状态 **3**（climate **2**）、器物状态 **8**。内容包 **v2** 固定包含38份定义及来源digest；部分动作等规则仍直接读取项目文件。当前只接受根52，旧根明确拒绝；[兼容政策](../engineering/compatibility.md)不承诺永久迁入链，真实fixture保持只读。
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
