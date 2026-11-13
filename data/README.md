# 内容资料

这里保存定义与开局素材，不保存运行世界。现行后端实际读取`definitions/items.json`、`construction.json`及`plants.json`；其他JSON是待选择迁移的内容，存在不等于已实现玩法。开局由当前kernel的terrain/world/nature/regions与可选scenarios装配，不读取旧scenario后端。

旧内容装配器与`compatibility/content_db_v42.json`对应的历史兼容机制已退役。旧schema、名称、模板字段与固定职业不约束新内核；采用内容时在实际领域解释，定义、开局、运行实例分开，不为旧格式恢复旧管线。

当前外观清单在[assets/art/catalog.json](../assets/art/catalog.json)，旧`humanoid_appearance.json`只属于退役技术样本，不被正式场景读取。

`items.json`当前装备条目用`slot`、`icon`、`stats`描述位置、临时图形符号和属性偏移；品质键、乘数和基础属性只由`kernel/items.gd`与`equipment.gd`解释，领域职责见[运行架构](../docs/engineering/architecture.md#库存装备与派生属性)。这些示例平衡值可调整，不是完整装备规则或素材定稿。普通试玩把一组装备放在#1背包与附近箱子中；`scenarios.capacity`仅装配明确的耐久压力初值，不改变定义或运行算法。
