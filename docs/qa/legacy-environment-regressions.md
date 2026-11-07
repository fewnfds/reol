# 旧 Q 环境回归的历史入口

本包将普通世界的冷热实现切换到环境场，并将普通存档边界改为根 schema 52、区域 schema 43。以下旧 Q 算法与旧热档成功迁入案例不再由当前普通测试入口运行；测试源码和历史 fixture 保留，不能据此宣称当前模型支持旧热档。新接入及存读边界仍须在对应版本实际验证。

## 退出当前入口的组

旧 Q 的单元存储、压缩、分组、分配、历史、查询复用与传递预算属于原实现的内部合同：

- [test_local_heat](../../tests/sim/test_local_heat.gd)
- [test_thermal_cell_store](../../tests/sim/test_thermal_cell_store.gd)
- [test_thermal_compressed_field](../../tests/sim/test_thermal_compressed_field.gd)
- [test_thermal_allocation](../../tests/sim/test_thermal_allocation.gd)
- [test_heat_geometry_reuse](../../tests/sim/test_heat_geometry_reuse.gd)
- [test_thermal_frozen_groups](../../tests/sim/test_thermal_frozen_groups.gd)
- [test_thermal_grouped_field](../../tests/sim/test_thermal_grouped_field.gd)
- [test_absolute_heat](../../tests/sim/test_absolute_heat.gd)
- [test_heat_query_reuse](../../tests/sim/test_heat_query_reuse.gd)
- [test_thermal_history](../../tests/sim/test_thermal_history.gd)
- [test_thermal_reclaim_probe](../../tests/sim/test_thermal_reclaim_probe.gd)
- [test_thermal_transfer_budget](../../tests/sim/test_thermal_transfer_budget.gd)

[test_legacy_heat_v1](../../tests/sim/test_legacy_heat_v1.gd) 和 [test_thermal_import](../../tests/sim/test_thermal_import.gd) 验证的是旧热模型或旧根档的成功迁入，随同作为历史案例保存。以上组的源码位于 `tests/sim/`，原文件和 fixture 均未改写。

当前入口新增 [test_world_environment_fields](../../tests/sim/test_world_environment_fields.gd) 和 [test_world_field_save_boundary](../../tests/runtime/test_world_field_save_boundary.gd)。带有业务、在途、有限设备或当前坏候选拒绝语义的其他混合组不按名称整体退役；它们的旧档样本需要分别重建或拆分。

## 在旧源码检出复现

历史入口固定于原 HEAD `2483a3771bc9f469509293a514fb0a059eefe095`。该版本的普通世界使用 `SimLocalHeat`，区域 schema 为 42；当时采用 Godot 4.7.2 stable。使用尚不存在的独立目录，在项目检出中执行：

```powershell
git worktree add --detach ../reol-legacy-2483a37 2483a3771bc9f469509293a514fb0a059eefe095
Set-Location ../reol-legacy-2483a37
python tools/godot.py doctor
python tools/godot.py check --test-timeout 1800
```

旧版本的 `check` 会导入并执行该版本的完整 `tests/run_tests.gd`，上述组作为其中的一部分运行，日志按组输出 `RUN` 和结果。该命令需要当时版本的引擎和项目依赖；它不证明当前新场或当前版本通过。不要将旧测试入口直接挂回当前普通模型，也不建立同时运行两套模型的测试入口。

本次仅整理入口和复现说明，没有运行上述历史回归；历史结果与约束仍以对应 SHA 的 QA 和日志为准。

## 同轮退役的普通入口

以下验收依赖旧根成功迁入或旧 Q 数值预算，不再代表新场合同；源码和原始 fixture 继续保留：`test_heat_amount_migration`、`test_thermal_device_migration`、`test_solar_migration`、`test_thermal_budget`。其当前设备/气候/坏候选/共同时间业务分别由 `test_thermal_devices`、`test_solar_rules`、`test_calendar_climate`、`test_world_environment_fields`、`test_world_field_save_boundary` 及对象动作测试承担。

`test_conflict_archive`、`test_conflict_perception_archive`、`test_herb_ecology_archive`、`test_spirit_source_archive`、`test_local_heat_archive` 是旧普通点击档的历史完整未来重放，随旧根退役；当前业务与进行中恢复继续由相应 `test_conflicts`/`test_conflict_perception`、`test_herb_ecology_rules`/`test_herb_irrigation`、`test_spirit_sources`/`test_spirit_source_continuity`、`test_artifact_warming`/`test_heat_source_amounts` 和普通 Main 当前重启验收承担。这不是每种旧场景都已在新格式跨进程重演的声明。

旧独立 `EnvironmentResponseSession` 和 `test_environment_event_boundary` 的双层 guard 验收退出当前入口；普通世界已拥有实际场，禁止旧会话再安装第二份状态或旁路物品来源提交。通用 field/目标编译/响应/缓存/事务纯组件测试仍运行，普通接缝由 `test_world_environment_fields` 和普通 Main 验收替代。历史诊断工具需要检出旧 SHA，不是当前游戏另一个可支持运行模型。

混合 runtime 组中的旧 archive 子函数改为真实旧档拒绝、原档和活世界不变，保留其当前正向业务和进行中存读。开发不把旧版本的成功导入断言改成空世界或新档冒充旧档。此登记只说明合同变化；新版本是否通过仍看最终 QA。

最终回归另发现`test_field_archives`仍用三个真实v40原档要求成功重放，现退出完整runner与`tools/qa/field_check.gd`的显式入口，原源码/fixture保留。相同三原档的拒绝、hash和活世界不变已有`test_drawing_migration`覆盖；当前真实旅途中与NPC路途中存读及独立Main相同未来分别由`test_field_opportunity_runtime`、`test_field_opportunity_absence`承担。戒指研究/引物的当前存读由`test_drawing_runtime`覆盖；不声称已在根52普通联合文件重放“该戒指拾取进行中”的完全相同旧场景，器物域局部候选及另一生命周期实物的在途联合恢复不等于这个专有场景。
