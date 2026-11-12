# 内容资料

这里保存定义与开局素材，不保存运行世界。现行后端实际读取`definitions/items.json`、`construction.json`及`plants.json`；其他JSON是待选择迁移的内容，存在不等于已实现玩法。开局由当前kernel的terrain/world/nature/regions与可选scenarios装配，不读取旧scenario后端。

旧内容装配器与`compatibility/content_db_v42.json`对应的历史兼容机制已退役。旧schema、名称、模板字段与固定职业不约束新内核；采用内容时在实际领域解释，定义、开局、运行实例分开，不为旧格式恢复旧管线。

当前外观清单在[assets/art/catalog.json](../assets/art/catalog.json)，旧`humanoid_appearance.json`只属于退役技术样本，不被正式场景读取。
