# 有限兼容首包：依赖清点

> 这是历史清点与候选退役合同，不是当前实现或工作顺序的证据。当前优先级只看[基础优先级](../../plans/foundation-priorities.md)，实际格式和验证见状态文档；旧R/W/F编号与下一步不构成队列。

状态：2026-11-05 R0a已实施并完成定向验证，审查及最终SHA回归接续；证据见[BASELINE](../../status/baseline.md)。本文记录静态清点、实际首包及后续候选，不扩大旧档支持承诺；当前授权与格式以[HANDOFF](../../status/handoff.md)为准，退役政策见[COMPATIBILITY](../../engineering/compatibility.md)。用户实际存档未另行扫描；本包保留其现有根档导入范围，历史fixture保持原样。

## 可单独清理的入口

[RegionalSimulation.restore](../../../scripts/sim/regional_simulation.gd) 内原区域版本30–37的八个逐级调用已删除：成功逐级转换最多到38，失败返回空字典，原 `_valid_world_shape` 要求区域41，两者都不能经此直接恢复成功。九个根迁移仍需的纯转换体移入[LegacyRegionalUpgrades](../../../scripts/persistence/legacy_regional_upgrades.gd)，仅将原整数检查显式限定到原函数，机械对比其余函数体不变；未留运行层兼容wrapper。[SessionSaveSchema](../../../scripts/persistence/session_save_schema.gd)按需加载新模块并保留原版本/形状校验，过期注释同步修正。

不能删除同一 `restore` 内的 `legacy_heat_v1` / `legacy_heat_v2` 专用分支：它们分别严格验证区域 39/热 1 和区域 40/热 2 的旧完整候选，在私有副本上适配当前校验；生产调用由 [ThermalImport](../../../scripts/persistence/thermal_import.gd) 经 [WorldRestoreFactory](../../../scripts/sim/world_restore_factory.gd) 发起。转换后的区域 41 还要再次通过当前候选。普通当前区域恢复、候选隔离及失败不改变活世界也必须保留。

## 仍有调用的历史转换

联合档的普通路径是 `WorldContinuityRuntime.load_game` → `WorldSessionSnapshot.stage` → `SessionSaveSchema.upgrade`；旧根档先经下表的机械转换到旧热边界，再由 `ThermalImport` 校验原内容、独立地图与完整旧候选、转换并复验当前候选。根 47 走热 v1 导入，根 48 走热 v2 导入，根 49 校验当前格式；更早的实际可接受输入仍受具体内容和形状校验约束，不能仅凭版本号承诺所有旧档有效。

独立村落未接联合会话时，`VillageRuntime.load_game` 直接调用同一根档升级，再用独立地图和 `VillageSimulation.from_snapshot` 验证；它不是 `WorldSessionSnapshot.stage` 的调用者。旧联合档也不能通过删除 `continuity` 来冒充独立村落，因为可能有其他域拥有的进行中操作和预约。

| 根档转换 | 区域转换 | `SessionSaveSchema` 调用的静态函数 |
| --- | --- | --- |
| 34 → 35 | 30 → 31 | `upgrade_conflicts` |
| 35 → 36 | 31 → 32 | `upgrade_conflict_perception` |
| 36 → 37 | 32 → 33 | `upgrade_site_affairs` |
| 37 → 38 | 33 → 34 | `upgrade_source_care` |
| 38 → 39 | 34 → 35 | `upgrade_capability_practice` |
| 39 → 40 | 35 → 36 | `upgrade_field_opportunities` |
| 40 → 41 | 36 → 37 | `upgrade_ring_use` |
| 41 → 42 | 37 → 38 | `upgrade_private_exchange` |
| 46 → 47 | 38 → 39 | `upgrade_heat_amounts` |

根42绑定固定`legacy_v42`内容；根43–46处理已绑定内容、装配输入、地图和地表等包络。上述静态函数现在仅在持久化层，仍是旧根档生产路径的一部分。热导入器及`LegacyHeatV1`、`LegacyHeatV2`同样仍被使用；它们校验原候选，不是独立的活运行模型。

## 地图、样本和回归依赖

普通新局使用 [`reol_flat_noise`](../../../data/scenarios/world_generation.json)，但 [WorldMapData](../../../scripts/sim/world_map_data.gd) 仍接受严格固定的旧 `reol_noise` 描述。静态读取真实根 34、35、37、40、41、42 及两份根 48 热 fixture，地图均为 `reol_noise` v1、seed 20261101、512 格。根 48 的[来源说明](../../../tests/fixtures/session_v48_thermal.md)记录旧代码和在途/未来样本。

当前格式也可能携带旧地图：[test_flat_world_runtime](../../../tests/runtime/test_flat_world_runtime.gd) 将真实根 42 正常导入并对比捕获结果与升级后的当前快照；`SessionSaveSchema` 对当前根档继续通过 `WorldMapData.valid_descriptor` 校验旧描述。故只缩减旧根版本不足以证明旧生成器可删除；先区分已有当前档与旧根档的地图依赖，不能用新平面地图冒充原丘陵。

真实旧档的来源和在途语义见 [fixture 索引](../../../tests/fixtures/README.md)。例如 [test_conflict_migration](../../../tests/runtime/test_conflict_migration.gd) 使用根 34，[test_source_loan_migration](../../../tests/runtime/test_source_loan_migration.gd) 使用根 36，[test_private_exchange_migration](../../../tests/runtime/test_private_exchange_migration.gd) 使用根 41；它们经普通 loader 恢复，不依赖区域旧版本的直接恢复成功。[test_heat_amount_migration](../../../tests/runtime/test_heat_amount_migration.gd)、[test_thermal_import](../../../tests/sim/test_thermal_import.gd) 和 [test_thermal_device_migration](../../../tests/runtime/test_thermal_device_migration.gd) 分别覆盖真实旧来源到 v1 边界及根 48/v2 来源和未来。前两者到根 47 的包络是从真实旧档沿既有转换得到，并非声称有独立根 47 原始 fixture。

[主测试 runner](../../../tests/run_tests.gd) 仍登记上述迁移及地图回归；`tools/qa/` 也有指向根 35、37、38、39、41 等真实样本的入口。决定以后收缩某个支持范围时，应先逐项盘点这些使用者、当前格式承接及用户档案，再另列迁移和退役包；不在本首包直接删除旧根入口、fixture 或旧地图。

## 首包验收与后续清理要求

1. 用可辨认的区域 30–37 历史输入验证直接 `restore` 拒绝，输入和原活世界的身体、器物、库存、账本、位置、时间及在途状态均不改变；覆盖当前区域正常恢复。
2. 经原普通入口继续验证现有真实旧根档及根 47/v1、48/v2 导入，保留原内容、地图、实物、时间、在途过程和同未来；分别覆盖联合与独立村落及坏候选的原子拒绝。原 fixture 和用户存档不可改写。
3. 验证当前根 49 联合与独立存读、旧地图升级后以当前格式存读、新平面开局及完整停开；拒绝混版、缺失必要事实和未知生成器。
4. R0a已由主代理完成doctor/导入与6组494项定向；精确范围及SHA见BASELINE，当前完整回归留对应SHA的CI，不本机/CI双跑。未来收缩其他旧档支持时仍须执行本节与兼容政策，不把本首包等同整条历史链退役。
