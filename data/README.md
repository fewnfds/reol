# 内容定义

这里仅保留当前代码实际使用的定义，不保存运行世界。

| 入口 | 解释者与用途 |
|---|---|
| `definitions/items.json` | Items/Equipment：物品键、装备槽位、图标、属性和武器配置引用 |
| `definitions/construction.json` | Facilities及营造UI：占地、操作位、材料、工期与设施参数 |
| `definitions/plants.json` | Nature及素材重建：六种植物的生境、生命周期、产物与来源 |
| `definitions/combat/library.tres` | 显式注册40份动作、24套配置；ACT定义在`combat/`，公共效果/状态/池/反应等在`actions/` |
| `definitions/decisions/library.tres` | 7套单位Policy，规则/序列与受信求值器共用原执行；[制作与绑定](../design/systems/unit_decision_framework.md#5-制作与绑定) |

Resource类型位于`scripts/sim/definitions/{actions,combat,decisions}/`，校验与只读编译入口为`action_defs.gd`/`decision_defs.gd`，Inspector增强为`addons/reol_combat_authoring/`。物品通过`combat_loadout`/`ai_loadout`引用配置，人物的`ability_loadout`可显式覆盖。新增同类技能见[制作合同](../design/systems/combat_framework/act_and_barrage.md#102-制作者新增技能的实际流程)。

开局由World与`kernel/scenarios.gd`、Terrain、Nature、Regions装配；实例的CD、弹体、状态和器物由各owner持有，不写回Resource。旧JSON装配、兼容数据库和旧scenario数据已删除，需要追溯时查Git；它们不定义新内核的schema或待迁移任务。

当前美术清单为[assets/art/catalog.json](../assets/art/catalog.json)。装备数值与练习初值是可调整样例，压力开局仅修改明确的初值，不提供另一套算法。
