# 内容定义

这里仅保留当前代码实际使用的定义，不保存运行世界。

| 入口 | 解释者与用途 |
|---|---|
| `definitions/items.json` | Items/Equipment：物品键、装备槽位、图标、属性和武器配置引用 |
| `definitions/construction.json` | 建造大类、小类、物品及材质。物品共享占地和用途，各材质指定成品 ID 和耗料 |
| `definitions/plants.json` | Nature及素材重建：植物生境、生命周期、产物与来源 |
| `definitions/combat/library.tres` | 显式注册40份动作、24套配置；ACT定义在`combat/`，公共效果/状态/池/反应等在`actions/` |
| `definitions/decisions/library.tres` | 7套单位Policy，规则/序列与受信求值器共用原执行；[制作与绑定](../design/systems/unit_decision_framework.md#5-制作与绑定) |
| `openings/qinghe_sect.tres` | 正常百人宗门的一次性布局/人物起点/任职与有限物资，经原owner采用；[制作入口](../design/systems/sect_life.md#当前正常开局的制作入口) |

`construction.json` 的 `materials` 用库存物品键表示材质。每个 `objects` 条目声明大类、小类、物品名和共享 `properties`。`variants` 按材质键声明成品 ID、名称和用量。`overrides` 按整项覆盖共享属性。建造目录与运行规格编译自同一份数据，现有成品 ID 供开局和存档继续识别。

Resource类型位于`scripts/sim/definitions/{actions,combat,decisions}/`，校验与只读编译入口为`action_defs.gd`/`decision_defs.gd`，Inspector增强为`addons/reol_combat_authoring/`。物品通过`combat_loadout`/`ai_loadout`引用配置，人物的`ability_loadout`可显式覆盖。新增同类技能见[制作合同](../design/systems/combat_framework/act_and_barrage.md#102-制作者新增技能的实际流程)。

World只建共同基础；`scripts/sim/scenarios/settlement_opening.gd`采用正常宗门Resource，`development_opening.gd`隔开旧赠物、木材和固定老师夹具。`kernel/scenarios.gd`保留战斗/混合/容量实验。实例的CD、弹体、状态和器物由各owner持有，不写回Resource；装配不进入运行期或读档后重放。旧JSON装配、兼容数据库和旧scenario数据已删除，需要追溯时查Git；它们不定义新内核的schema或待迁移任务。

当前美术清单为[assets/art/catalog.json](../assets/art/catalog.json)。装备数值与练习初值是可调整样例，压力开局仅修改明确的初值，不提供另一套算法。
