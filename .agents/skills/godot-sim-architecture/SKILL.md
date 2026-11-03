---
name: godot-sim-architecture
description: 为 Godot 4.7 的殖民模拟/开放世界/RPG 设计架构：固定 tick、节点组合、实体注册、数据驱动、区块流式、版本化存档、性能预算。写新系统、重构、卡顿、存档问题时使用。
---

# Godot 模拟游戏架构（4.7）

## 何时用

- 新建一个系统（需求、工作、战斗、建造、经济、任务）。
- 决定代码放哪、用什么数据结构、怎么和 UI 解耦。
- 10 个 NPC 就掉帧、存档越写越乱、读档后引用失效。
- 想引入 ECS/行为树/事件总线，先判断值不值。

**不适用**：纯 UI 动画、单个小游戏机制、Godot 基础语法（用 `godot-gdscript`）。

---

## 1. 先定三条底线

1. **模拟和渲染分离**：模拟固定 tick；渲染每帧插值。
2. **数据与行为分离**：定义/数值在 `Resource`/JSON；代码只读定义。
3. **依赖方向向下**：UI → 系统 → 实体 → 世界 → 数据；不要反向。

违反这三条，后期一定痛。

---

## 2. 固定 tick

### 2.1 不要用 `_process` 做模拟

- 帧率不稳定 → 结果不可复现。
- 暂停/快进会污染物理和动画。
- 测试无法“快进 1 小时”。

### 2.2 GameClock

```gdscript
# scripts/autoload/game_clock.gd
extends Node

signal tick(tick_index: int)
signal hour_changed(hour: int)
signal day_changed(day: int)

@export var ticks_per_second: int = 10
@export var minutes_per_tick: int = 1

var speed: float = 1.0
var paused: bool = false
var tick_index: int = 0
var minute_of_day: int = 8 * 60

var _accumulator: float = 0.0

func _process(delta: float) -> void:
    if paused:
        return
    _accumulator += delta * speed
    var step := 1.0 / float(ticks_per_second)
    var budget := 8                  # 卡顿后最多补 8 tick，防螺旋
    while _accumulator >= step and budget > 0:
        _accumulator -= step
        budget -= 1
        _advance()
    if budget == 0:
        _accumulator = 0.0

func _advance() -> void:
    tick_index += 1
    tick.emit(tick_index)

    minute_of_day += minutes_per_tick
    if minute_of_day >= 24 * 60:
        minute_of_day = 0
    if tick_index % (ticks_per_second * 60) == 0:
        hour_changed.emit(get_hour())
    if tick_index % (ticks_per_second * 60 * 24) == 0:
        day_changed.emit(get_day())

func get_hour() -> int:
    return int(minute_of_day / 60.0)

func get_day() -> int:
    return int(tick_index / float(ticks_per_second * 60 * 24)) + 1
```

规则：
- 速度用 `speed`（0/1/3），不要 `Engine.time_scale`。
- 暂停用 `paused`；UI 节点设 `PROCESS_MODE_ALWAYS`。
- 补 tick 有上限；宁可丢时间，不要卡死。
- 单位/建筑订阅 `tick`，不要各自 `_process`。

### 2.3 分级更新

不是所有系统都要 10Hz：

| 系统 | 频率 |
|---|---|
| 移动/战斗 | 10Hz（或物理 60Hz） |
| 需求衰减 | 1Hz |
| 工作评估 | 每 0.5–1s |
| 房间/温度 | 每 2–5s |
| 经济/事件 | 每游戏小时/天 |
| 寻路 | 事件驱动 + 重试上限 |

用一个 `TickScheduler` 或简单的计数器分流：

```gdscript
var _slow_accum := 0.0
func _on_tick(_i: int) -> void:
    _slow_accum += 1.0 / GameClock.ticks_per_second
    if _slow_accum >= 1.0:
        _slow_accum = 0.0
        _update_needs()
```

---

## 3. 实体模型

### 3.1 节点组合，不写完整 ECS

```
Pawn (CharacterBody2D)
├── Sprite2D
├── CollisionShape2D
├── HealthComponent (Node)
├── NeedsComponent (Node)
├── InventoryComponent (Node)
├── JobExecutor (Node)
└── NavigationAgent2D
```

- 每个实体一个 `.tscn`，根脚本 `class_name Pawn extends CharacterBody2D`。
- 能力用子节点；纯数据用 `Resource`。
- 不要做 10 层继承；用组合和信号。

### 3.2 Entity 基类 + 注册表

```gdscript
class_name Entity
extends Node2D

@export var def_id: StringName
var entity_id: int = 0

func _enter_tree() -> void:
    if entity_id == 0:
        entity_id = EntityRegistry.allocate_id()
    EntityRegistry.register(self)

func _exit_tree() -> void:
    EntityRegistry.unregister(self)
```

```gdscript
# scripts/autoload/entity_registry.gd
extends Node

var _next_id: int = 1
var _by_id: Dictionary[int, Entity] = {}

func allocate_id() -> int:
    var id := _next_id
    _next_id += 1
    return id

func register(e: Entity) -> void:
    _by_id[e.entity_id] = e

func unregister(e: Entity) -> void:
    _by_id.erase(e.entity_id)

func get_entity(id: int) -> Entity:
    return _by_id.get(id)
```

规则：
- 所有需要存档/跨系统引用的实体都要有稳定 `entity_id`。
- 不要用节点路径做 ID。
- 实体释放时注销；槽位/工作预约也要释放。

### 3.3 不要每帧扫全树

```gdscript
# 错
for pawn in get_tree().get_nodes_in_group("pawns"):
    ...

# 对：注册表 + 事件
for id in EntityRegistry.pawn_ids:
    ...
```

更好：系统维护自己的 `Array[Pawn]`，在 `entity_spawned/died` 时增删。

---

## 4. 数据驱动

### 4.1 Resource 定义

```gdscript
class_name ItemDef
extends Resource

@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export_range(1, 9999) var max_stack: int = 99
@export var tags: Array[StringName] = []
```

- `.tres` 放 `res://data/items/`。
- 启动时 `DataDB` 扫描/注册，校验重复 ID/空字段/引用。
- **Resource 默认共享**；运行时状态不要写进 Def。

### 4.2 什么时候用 JSON

- 大量表格（掉落、配方、对话、地图）。
- 外部工具生成。
- 需要清晰 diff。
- 存档。

```gdscript
var text := FileAccess.get_file_as_string("res://data/recipes.json")
var data: Variant = JSON.parse_string(text)
if data == null:
    push_error("recipes.json 解析失败")
```

### 4.3 ID 规则

- `StringName`，稳定、可跨语言。
- 命名：`wood`、`stone`、`build_wall_wood`、`job_haul`。
- 不要用显示名做 ID。
- 不要用数组下标做存档 ID。

---

## 5. 系统与事件

### 5.1 EventBus

```gdscript
extends Node

signal entity_spawned(entity: Node)
signal entity_died(entity: Node)
signal job_posted(job: Job)
signal job_completed(job: Job, pawn: Node)
signal building_completed(building: Node)
signal notification_requested(text: String, kind: StringName)
```

规则：
- 低频、跨系统用 EventBus。
- 高频（每帧移动/每次伤害）用直接调用或局部 signal。
- signal 只传数据/节点，不传 UI。
- 订阅者在 `_exit_tree()` 断开（或依赖自动断开）。

### 5.2 系统边界

| 系统 | 拥有 | 不拥有 |
|---|---|---|
| `JobBoard` | 工作列表、预约 | Pawn 移动 |
| `Pawn` | 自己的需求/状态/执行器 | 全局工作表 |
| `World` | 地形/区块/导航 | 实体 AI |
| `CombatSystem` | 伤害结算/阵营 | 动画/UI |
| `GameState` | 玩家/殖民地/flags | 每帧逻辑 |

---

## 6. 世界与区块

### 6.1 v0.1 单地图

- 128×128；一个 `TileMapLayer` 地面 + 一个墙体 + 一个装饰。
- 地图数据 JSON/ASCII；启动加载。
- `AStarGrid2D` 寻路。
- 不要一上来做流式；先把单地图跑顺。

### 6.2 v1+ 区块

```gdscript
class_name WorldChunk
extends Node2D

const SIZE := 64
var coord: Vector2i
var dirty: bool = false
```

- 64×64；加载半径 2，卸载半径 3。
- 地形由 seed 生成；POI 数据表放置。
- 只存 deltas：挖掉的格子、建筑、物品、实体。
- 区块场景用 `ResourceLoader.load_threaded_request`。

### 6.3 寻路

```gdscript
var astar := AStarGrid2D.new()
astar.region = Rect2i(0, 0, 128, 128)
astar.cell_size = Vector2(32, 32)
astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
astar.update()
var path: Array[Vector2i] = astar.get_id_path(start, goal)
```

- 地图变化只更新受影响格子。
- 路径缓存；失败重试上限（3 次）；不可达要释放工作。
- 大地图/连续空间用 `NavigationAgent2D`；网格 sim 用 AStarGrid2D。

---

## 7. 存档

### 7.1 结构

```json
{
  "version": 1,
  "seed": 123456,
  "clock": { "tick": 1200, "minute": 480 },
  "player": { "id": 1, "pos": [10.5, 20.0], "hp": 80 },
  "entities": [
    { "type": "pawn", "id": 2, "def": "pawn_cook", "pos": [4, 5], "needs": { "hunger": 0.4 } }
  ],
  "chunks": {
    "0,0": { "removed": [[3, 4]], "buildings": [] }
  },
  "flags": { "tutorial_done": true }
}
```

### 7.2 规则

- 只存 deltas；地形由 seed 重建。
- 存 ID/定义 ID，不存节点路径/Resource 对象。
- `version` + 迁移链。
- 原子写：`.tmp` → flush → rename；保留 `.bak`。
- 读档：暂停 → 重建世界 → 应用 deltas → 生成实体 → 绑定 UI → 恢复。
- 每次结构变更加 roundtrip 测试。

```gdscript
const SAVE_VERSION := 1

func save_game(path: String) -> Error:
    var data := {
        "version": SAVE_VERSION,
        "clock": GameClock.to_dict(),
        "entities": EntityRegistry.to_array(),
    }
    var tmp := path + ".tmp"
    var f := FileAccess.open(tmp, FileAccess.WRITE)
    if f == null:
        return FileAccess.get_open_error()
    f.store_string(JSON.stringify(data, "\t"))
    f.flush()
    f.close()
    return DirAccess.rename_absolute(
        ProjectSettings.globalize_path(tmp),
        ProjectSettings.globalize_path(path)
    )
```

---

## 8. 性能

### 8.1 预算

- 60 FPS；sim tick < 8ms（12 Pawn + 50 建筑）。
- 区块加载 < 4ms/帧（异步）。
- Draw calls < 500（2D）。
- 内存 < 1GB。

### 8.2 手段

- `TileMapLayer` 代替成千上万 Sprite。
- 草地/装饰用 `MultiMeshInstance2D`。
- 屏幕外实体降频/禁用 `process_mode`。
- 对象池：投射物、伤害数字、掉落。
- 缓存 `get_node`/`get_nodes_in_group` 结果。
- A* 限制节点数/重试。
- 世界生成/大 JSON 放 `WorkerThreadPool`。
- 用 Profiler/`Performance` 实测，不猜。

### 8.3 常见热点

```gdscript
# 每帧全树扫描
get_tree().get_nodes_in_group("pawns")

# 每帧 load
load("res://scenes/x.tscn")

# 每帧新建数组/字典
var list := []
for e in ...:
    list.append(e)

# 每帧 connect
signal.connect(...)
```

改成：注册表、缓存、对象池、一次性连接。

---

## 9. 测试

- 纯逻辑放 `RefCounted`，不依赖场景树。
- 注入 clock/seed，测试可重复。
- 测试命名：`test_<system>_<behavior>`。
- 必须覆盖：边界、失败、存档 roundtrip、工作预约。
- 场景测试：生成小场景 → 跑 N tick → 断言状态。
- 每次改完跑 `python tools/godot.py check`。

---

## 10. 反模式清单

- ❌ 20 个 autoload，互相引用。
- ❌ 在 `_process` 里做需求/工作/经济。
- ❌ 每帧 `get_nodes_in_group` / `find_children` / `load`。
- ❌ 用节点路径/显示名做存档 ID。
- ❌ 把运行时状态写进共享 `Resource`。
- ❌ 10 层继承 `Entity → Character → Humanoid → Pawn → Worker → ...`。
- ❌ 为了“以后可能”做完整 ECS/事件溯源/依赖注入框架。
- ❌ `await` 没有超时/取消。
- ❌ 手写 `.tscn` 的 UID/资源引用。
- ❌ 用 `assert()` 做玩家输入校验。
- ❌ 先做 UI 再做逻辑（UI 会绑死错误的数据结构）。

---

## 11. 新系统检查清单

- [ ] 这个系统拥有什么数据？边界在哪？
- [ ] 它订阅哪个 tick/信号？频率多少？
- [ ] 数据放 `data/` 还是代码常量？
- [ ] 需要新的 autoload 吗？能不能用现有系统？
- [ ] 失败/取消/单位死亡时怎么清理？
- [ ] 存档要存什么？读档怎么恢复？
- [ ] 最坏情况性能（12 Pawn/100 建筑）？
- [ ] 怎么测试？最小复现场景？
- [ ] UI 需要什么信号？会不会反向依赖？
- [ ] 文档/ADR 更新了吗？

---

## 12. 相关技能

- `godot-gdscript` — 语法/类型/信号
- `godot-nodes-scenes` — 场景/实例化/autoload
- `colony-sim-systems` — 需求/工作/建造
- `open-world-2d` — 区块/生成/流式
- `save-systems` — 存档模式
- `performance-optimization` — 性能排查
- `godot-verify` — 验证流程
