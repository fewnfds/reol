# data/ 约定

> 所有**定义/数值/内容**放这里；代码只读定义，不硬编码。

---

## 目录（按需创建）

```
data/
├── items/          # ItemDef .tres
├── buildings/      # BuildingDef .tres
├── pawns/          # PawnDef .tres
├── jobs/           # JobDef .tres
├── recipes/        # RecipeDef .tres
├── events/         # EventDef .tres / .json
└── world/          # biome / POI / loot tables / maps
```

---

## Resource 还是 JSON？

| 场景 | 选择 |
|---|---|
| 设计师在 Inspector 里调 | `.tres`（类型安全、可拖拽） |
| 大量表格/外部工具生成 | `.json`（易批量、diff 清晰） |
| 存档 | `user://` JSON（不在这里） |
| 本地化 | CSV/PO（后续） |

---

## ID 规则

- 用 `StringName`，稳定、可跨语言。
- 小写 `snake_case`：`wood`、`stone`、`build_wall_wood`、`job_haul`。
- 不要用显示名做 ID。
- 不要用数组下标做存档 ID。
- 改 ID = 破坏存档；必须改时写迁移。

---

## 校验

启动时（debug build）：
- 重复 ID。
- 必填字段为空。
- 引用的 scene/texture/resource 不存在。
- 配方引用的 item 不存在。
- 数值超出范围。

失败时 `push_error` 并列出文件路径；不要静默跳过。

---

## 不要放什么

- 运行时状态（Pawn 当前 HP、建筑进度、玩家位置）。
- 存档文件。
- 临时/生成缓存。
- 密钥/API key。
- 大段代码/脚本。

---

## 命名示例

```
data/items/wood.tres
data/items/stone.tres
data/buildings/wall_wood.tres
data/buildings/bed_simple.tres
data/recipes/planks_from_wood.tres
data/pawns/pawn_cook.tres
data/world/biomes/forest.tres
data/world/pois/camp.json
```
