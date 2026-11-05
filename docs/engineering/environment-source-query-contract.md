# 地面环境来源查询合同（A1）

这是权威开发接口，不是玩家鉴定、可见属性或新的运行环境。普通 Main 仍由原冷热模型负责实际后果；来源查询没有温度、五行残留或时间推进。验收见[来源QA](../qa/20261105_environment_source_bindings.md)。

## 入口和定义

`EnvironmentSourceDefinitions.configure(raw)` 严格验证一次配置；失败不发布，成功后不可替换。输入是 `data/definitions/environment_sources.json` 的候选 schema v1，未加入普通内容包路径和存档。需要调用者显式加载，不能读取旧档时自动补能力。

- 根：`version/profiles/bindings`；绑定分 `artifacts/materials`。
- profile：木火土金水五个非负整数、单项有符号 `thermal_grade`、`radius_cells`、`activation/origin`。冷热正热负冷，1000表示1级；本接口两端限制10000，五行0–10000。范围只是当前支持合同，不限制未来世界设定。
- 半径只有2/4/8/16；激活只支持 `intrinsic`，原点只支持 `footprint_anchor`。未知字段、悬空绑定、双冷热字段及越界值拒绝，不静默修补。
- 可以多种定义共用一个profile。显式全零profile表示已知不发源；缺绑定是 `profile_missing`，不能当作零。
- `profile("artifact"|"material", id)` 和 `to_dict()` 返回独立副本；`digest()` 是规范化整数、排序键后的SHA-256，标识这份外部配置。绑定的器物定义名必须存在于该世界。

`SimEnvironmentSourceBindings.configure(world, definitions)` 一次绑定世界的弱引用，保留不可变定义和距离模板；不持有物品、数量、位置或持续来源目录。原世界独立恢复后，用同一显式定义重新绑定即可。旧结果是历史快照，不是实时句柄。

## 单物投影

`project(reference)` 支持现有完整引用：

| 原对象 | 输入 | 原事实 |
|---|---|---|
| 地面独特实物 | `{kind:"artifact", id}` | artifacts的定义、归属，加ground的活跃位置 |
| 地面材料堆 | `{kind:"stock", domain:"village", region, container, item}` | 原region.inventory数量，加ground的活跃位置 |

成功返回 `status/source_id/reference/profile_id/cell/size/quantity/elements/thermal_grade/radius_cells` 和范围元数据。`status` 为 `source` 或 `no_source`。一堆1份和10000份来源强度相同；数量只是原账本投影，不是场乘数。

多格物一份身份、一处点源：锚格加 `floor((size−1)/2)`，偶数向左上；`size` 保留完整占地，不影响原摆放/通行规则。

携物、容器内物和旧site固定位置为 `unsupported_location`；鸟类容器为 `unsupported_domain`；身体、墙、植物未接本接口。没有计算不等于游戏已实现屏蔽。移除实物、已清空或合并撤销的历史堆返回 `not_found`。

## 局部基础目标

`sample_base(cell, budget=16384)` 在原ground分桶上查询最大配置半径覆盖区，地图边界裁剪；按实物完整占地找候选并去重。账务region不是空间隔离，同一全局格会受邻近不同账本物品影响。

距离核在configure时生成有限模板，查询只查表；使用整数欧氏距离的线性衰减，中心满值、半径边界及以外为零。所有值用整数定点截断；冷热分别先按绝对等级衰减，效果对称。

- 五行分别取最大有效值，不求和。
- signed冷热派生正侧最大值H和负侧绝对最大值C，净值H−C。`hot_grade/cold_grade` 只是本次结果的派生极值，不是物品两项属性。
- 强来源移走后重新读取实际存活来源，弱来源自然接替。不从max中减掉旧值。

工作预算计原ground桶访问、候选访问/匹配和逐候选投影。预算1–1000000，工作单位不是毫秒。失败返回 `ok=false/complete=false/reason/work_used`，不含貌似完整的五行或冷热值。预算可重试且不改世界；不是跨帧准备句柄。

成功带 `complete=true/elements/thermal_grade/hot_grade/cold_grade/source_count/candidate_count/work_used`。共同元数据为 `visibility=authority_only`、`scope=active_ground_base_targets`、`world_time_ms/config_digest/live=false`。查询不授予交互权限，不写玩家认知。

## 时刻、变化与后续边界

世界欠算时返回 `world_has_backlog`，附近来源的区域时间不一致返回 `stale_source`；来源缺配置或归属不一致明确失败，不结算区域以掩盖旧值。完全同步且没有来源才是完整零场。

本接口每次直接读原owner，所以原生命周期生成、搬运、收起、落地、拆合和移除成功后的下一次查询立即一致。没有提交订阅者、持久场缓存或需要补写的来源副本，也不改变原命令失败和幂等规则。

这不是原物—缓存—实际响应联合事务。未来接持续场缓存与响应时仍须变更前prepare、预算续算、复验和同步发布；不能依赖本包只读投影或提交后signal冒充原子提交。也不能在每个格每帧反复调用这个诊断接口来模拟全图刷新；批量场更新须复用局部失效/packed缓存等专门路径，并另做联合性能验收。
