# Reol — 目标技术架构（v0.2）

> 状态：**已定方向**。随着原型验证会调整；重大变更记录到 `docs/DECISIONS.md`。
> 引擎：Godot 4.7.2 / GDScript / **2D 等距 + 高度层**。
> 原则：**先能跑，再抽象；数据驱动；固定 tick；小系统组合。**

---

## 1. 目标与非目标

### 目标
- 支持一个 **会持续运转** 的小世界：时间、NPC、工作、事件、宗门、势力。
- 支持 **玩家角色** 与 **宗门/势力管理** 两种视角在同一场景中切换。
- 支持 **512×512 首区、64×64 区块流式加载**；远区抽象模拟，近区实例化。
- 支持 **2D 等距 + 高度层 + 战争迷雾**；固定角相机，平移/缩放。
- 支持 **版本化存档**，读旧档不炸。
- 支持 **无头测试** 和 AI 自动验证。
- 60 FPS / 模拟 tick < 8ms / v0.1 10–20 个活跃 Pawn，v1 30–50。

### 非目标（v0.1）
- 联机、服务器权威、回滚网络。
- 真 3D、自由旋转/俯仰、体素破坏、真 3D 空战。
- 完整 ECS、Job System 级并行、GPU 皮肤。
- 无限世界；首区之外只做抽象模拟。
- 复杂流体/温度/气体模拟。
- LLM 核心模拟、模组沙箱、脚本热重载。

---

## 2. 分层

```
┌─────────────────────────────────────────────────────┐
│ UI / Input                                          │
│  HUD · 建造菜单 · 单位面板 · 对话 · 地图 · 暂停      │
└──────────────────────┬──────────────────────────────┘
                       │ signals / commands
┌──────────────────────▼──────────────────────────────┐
│ Systems                                             │
│  JobBoard · Combat · Craft · Needs · Quest          │
│  Faction · Reputation · Rank · WorldSim · Economy   │
└──────────────────────┬──────────────────────────────┘
                       │ queries / mutations
┌──────────────────────▼──────────────────────────────┐
│ Entities                                            │
│  Player · Pawn · Animal · Building · Item · Projectile │
└──────────────────────┬──────────────────────────────┘
                       │ spatial queries
┌──────────────────────▼──────────────────────────────┐
│ World                                               │
│  ChunkManager · IsoGrid · FogOfWar · Navigation     │
│  Time · Weather · POI · Spawner                     │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│ Data                                                │
│  Resource (.tres) · JSON · Locale · Save            │
└─────────────────────────────────────────────────────┘
```

**依赖方向只能向下。** UI 不拥有游戏状态；系统不直接操作 UI；实体不反向依赖系统 autoload
（通过 signal 或注入）。

---

## 3. 目录结构（目标）

```
res://
├── addons/                 # 第三方插件，不手改
├── assets/
│   ├── art/                # 精灵、TileSet、UI、VFX
│   ├── audio/              # sfx、music、ambience
│   ├── fonts/
│   └── third_party/        # 每个素材包带 LICENSE
├── data/
│   ├── items/              # ItemDef .tres
│   ├── buildings/          # BuildingDef .tres
│   ├── jobs/               # JobDef .tres
│   ├── recipes/            # RecipeDef .tres
│   ├── pawns/              # PawnDef .tres
│   ├── factions/           # FactionDef / RankDef .tres
│   ├── origins/            # OriginDef .tres
│   ├── events/             # EventDef .tres / .json
│   └── world/              # biome / POI / loot tables
├── scenes/
│   ├── boot.tscn
│   ├── main.tscn           # 世界 + HUD 根
│   ├── world/              # chunk、POI、weather
│   ├── entities/           # player、pawn、building、item
│   ├── ui/                 # hud、menus、panels
│   └── fx/
├── scripts/
│   ├── autoload/           # GameClock、EventBus、GameState...
│   ├── core/               # 纯逻辑：ids、rng、save、utils
│   ├── world/              # chunk、iso grid、fog、nav、time、weather
│   ├── entities/           # entity、pawn、building、item
│   ├── ai/                 # needs、jobs、utility、behavior、action API
│   ├── systems/            # combat、craft、quest、faction、reputation、rank
│   ├── sim/                # world/region tick、缺席战斗结算、传闻
│   └── ui/                 # hud、panels、widgets
├── tests/
│   ├── run_tests.gd
│   └── cases/              # 纯逻辑测试
├── tools/
│   ├── godot.py
│   └── mcp/godot_mcp.py
└── docs/
```

---

## 4. Autoload（按需创建）

| Autoload | 何时创建 | 职责 | 不应该做 |
|---|---|---|---|
| `EventBus` | 第一个跨系统事件 | 全局 typed signals | 存游戏状态 |
| `GameClock` | 第一个时间/需求系统 | tick、暂停、速度、日/夜 | 直接改实体 |
| `EntityRegistry` | 第一个需要按 ID 查找的实体 | ID 分配、注册/注销、查询 | 每帧扫描全树 |
| `GameState` | 第一个存档字段 | 玩家/宗门/任务 flags | 变成万能单例 |
| `JobBoard` | 第一个工作系统 | 工作发布、认领、预约、完成 | 直接控制 Pawn |
| `SaveManager` | 第一次存档 | 版本、序列化、迁移、原子写 | 知道每个系统的细节 |
| `World` | 第一个区块/地图 | 区块流式加载、地图查询 | 承担所有玩法 |
| `WorldSim` | 第一个远区模拟 | World/Region tick、缺席战斗结算、传闻 | 直接创建场景/节点 |
| `FactionRegistry` | 第一个阵营/声望 | 阵营定义、关系矩阵、声望查询 | 承担内政玩法 |

> **不要一次创建所有 autoload。** 每个 autoload 都是一个全局依赖；先有需求再建。

### EventBus 示例

```gdscript
# scripts/autoload/event_bus.gd
extends Node

signal game_tick(tick_index: int)
signal hour_changed(hour: int)
signal day_changed(day: int)
signal entity_spawned(entity: Node)
signal entity_died(entity: Node)
signal job_posted(job: Job)
signal job_completed(job: Job, pawn: Node)
signal item_stored(item: Node, stockpile: Node)
signal building_completed(building: Node)
signal combat_started(attacker: Node, target: Node)
signal notification_requested(text: String, kind: StringName)
```

规则：
- signal 只传 **数据/节点引用**，不传 UI。
- 连接方在 `_ready()` 连接，在 `_exit_tree()` 断开（或依赖节点释放自动断开）。
- 高频事件不要走 EventBus（每帧移动、每个伤害数字）；直接调用或局部 signal。

---

## 5. 模拟 tick 与时间

### 5.1 为什么不用 `_process` 做模拟

- 渲染帧率不稳定，模拟结果会随机器变化。
- 速度控制、暂停、快进会污染物理。
- 难以测试。

### 5.2 固定 tick

- 渲染：`_process(delta)`，只做插值/视觉。
- 物理：`_physics_process(delta)`，60Hz，只做移动/碰撞。
- 模拟：`GameClock` 以 **10 tick/s** 发出 `tick`，系统订阅。

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
var total_minutes: int = 0

var _accumulator: float = 0.0

func _process(delta: float) -> void:
    if paused:
        return
    _accumulator += delta * speed
    var step: float = 1.0 / float(ticks_per_second)
    var budget: int = 8                 # 防止卡顿后螺旋
    while _accumulator >= step and budget > 0:
        _accumulator -= step
        budget -= 1
        _advance_tick()
    if budget == 0:
        _accumulator = 0.0

func _advance_tick() -> void:
    tick_index += 1
    var prev_day: int = get_day()
    var prev_hour: int = get_hour()
    total_minutes += minutes_per_tick
    tick.emit(tick_index)
    if get_hour() != prev_hour:
        hour_changed.emit(get_hour())
    if get_day() != prev_day:
        day_changed.emit(get_day())

func get_day() -> int:
    return total_minutes / 1440

func get_hour() -> int:
    return (total_minutes / 60) % 24

func get_minute() -> int:
    return total_minutes % 60
```

**速度控制**用 `speed`，不要用 `Engine.time_scale`：
- `0` 暂停（或 `paused`）
- `1` 正常
- `3` 快进
- 暂停时 UI 仍响应：相关节点 `process_mode = PROCESS_MODE_ALWAYS`。

### 5.3 时间单位

内部统一用 **游戏分钟**：
- 1 tick = 1 游戏分钟（10 tick/s → 1 游戏小时 = 6 秒真实时间）
- 一天 24 小时 = 1440 tick = 144 秒真实时间（2.4 分钟）
- 这个比例适合“30 分钟体验一次昼夜”；后续可调。

### 5.4 分层时钟

| 层 | 频率 | 做什么 | 不做什么 |
|---|---|---|---|
| World | 每游戏天 | 势力资源/外交/战争/领袖/教义 | 不创建节点、不寻路 |
| Region | 每游戏小时 | 军队/POI/宗门政策/资源 | 不模拟单个 NPC |
| Settlement | 每几秒/游戏分钟 | 生产/职位/需求汇总 | 不跑物理 |
| Local | 10Hz | Pawn/工作/战斗/物理 | 不做全图扫描 |
| Detail | 每帧 | 动画/插值/UI/粒子 | 不改模拟状态 |

- 远区只跑 World/Region；靠近时把数据“提升”为 Local 实体，离开时“降级”。
- 具名 NPC 个体持久化；普通 NPC 按 cohort 聚合。
- 每个领域独立种子 RNG；存档记录 `sim_time`；读档补算设上限。

### 5.5 局部时间缩放（子弹时间）

- 每个 actor 有 `time_scale: float = 1.0`。
- 移动、AI 决策、冷却、投射物更新都乘自己的 `delta * time_scale`。
- 不用全局 `Engine.time_scale`，避免 UI/玩家输入/动画被一起拖慢。
- 暂停用 `GameClock.paused`；暂停时 UI 节点 `PROCESS_MODE_ALWAYS`。

---

## 6. 实体模型

### 6.1 选择：节点组合，不是完整 ECS

Godot 的节点树 + 脚本组合已经足够。完整 ECS 会带来：
- 与场景/编辑器脱节；
- 调试困难；
- 对 3–50 个实体是过度设计。

**采用：**
- 每个实体一个场景（`.tscn`），根节点挂脚本。
- 能力用子节点/组件表达：`HealthComponent`、`NeedsComponent`、`InventoryComponent`、`JobExecutor`。
- 纯数据用 `Resource`。
- 系统通过 `EntityRegistry` 和 signal 交互。

### 6.2 Entity 基类

```gdscript
# scripts/entities/entity.gd
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

### 6.3 组件示例

```gdscript
# scripts/entities/components/health_component.gd
class_name HealthComponent
extends Node

signal changed(current: int, maximum: int)
signal died

@export var max_hp: int = 100
var hp: int

func _ready() -> void:
    hp = max_hp

func damage(amount: int) -> void:
    if hp <= 0:
        return
    hp = maxi(hp - amount, 0)
    changed.emit(hp, max_hp)
    if hp == 0:
        died.emit()
```

### 6.4 实体注册表

```gdscript
# scripts/autoload/entity_registry.gd
extends Node

var _next_id: int = 1
var _by_id: Dictionary[int, Entity] = {}

func allocate_id() -> int:
    var id := _next_id
    _next_id += 1
    return id

func register(entity: Entity) -> void:
    _by_id[entity.entity_id] = entity

func unregister(entity: Entity) -> void:
    _by_id.erase(entity.entity_id)

func get_entity(id: int) -> Entity:
    return _by_id.get(id)
```

> 注意：`Dictionary[int, Entity]` 需要 Godot 4.4+；4.7.2 支持。若团队不熟，先用普通 `Dictionary`。

---

## 7. 数据驱动

### 7.1 用 Resource 还是 JSON？

| 场景 | 选择 | 理由 |
|---|---|---|
| 设计师在 Inspector 里调 | **Resource (.tres)** | 类型安全、可拖拽、可继承 |
| 大量表格/生成数据 | **JSON** | 易批量生成、diff 清晰、外部工具友好 |
| 存档 | **JSON** | 可读、可迁移、跨版本 |
| 地图 | **JSON + 压缩** | 可读、可版本控制 |
| 本地化 | **CSV / PO** | 翻译工具友好 |

### 7.2 定义资源

```gdscript
# scripts/core/defs/item_def.gd
class_name ItemDef
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export_range(1, 9999) var max_stack: int = 99
@export var tags: Array[StringName] = []
```

```gdscript
# scripts/core/defs/building_def.gd
class_name BuildingDef
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var scene: PackedScene
@export var size: Vector2i = Vector2i.ONE
@export var build_cost: Dictionary[StringName, int] = {}
@export var work_amount: float = 10.0
@export var blocks_movement: bool = true
```

规则：
- `id` 用 `StringName`，稳定、可跨语言。
- 定义资源放在 `res://data/`，由 `DataDB` 在启动时扫描/注册。
- **不要在代码里写 `if item_id == "wood"`**；用 tags/属性/策略。

### 7.3 数据校验

启动时（debug build）：
- 检查重复 ID。
- 检查必填字段。
- 检查引用的 scene/icon 存在。
- 检查配方引用的 item 存在。
- 失败时 `push_error` 并列出文件路径，不要静默。

---

## 8. 世界与区块

### 8.1 v0.1

- 首区 **512×512**；区块 **64×64**（8×8）；加载半径 2（5×5），卸载半径 3。
- 每个区块 3 层：ground / walls / props；等距 `TileMapLayer` + Y-sort。
- 地形来源：seed + 规则生成（先简单噪声/手工骨架），POI 从数据表放置。
- 地图尺寸不硬编码；区域元数据 + 世界分区。
- 只持久化 **deltas**：改格、建造、物品、实体状态。
- 区块加载用 `ResourceLoader.load_threaded_request()` 或后台生成；每帧最多 1 个；不要同步加载大场景。

### 8.2 等距坐标与高度

- 逻辑坐标 `cell: Vector2i`；世界坐标 `cell_to_world(cell)`；等距 2:1。
- 每格 `elevation: int`（0–3）；实体 `altitude: int`（0/1/2）。
- 渲染 Y 偏移：`-elevation * ELEVATION_PX - altitude * ALTITUDE_PX`。
- 影子留在 `ground_position`；随 altitude 变小/变淡。
- Y-sort 用脚底世界 Y，不用屏幕 Y。
- 悬崖/高差：`elevation_delta > 1` 视为不可走；`1` 可走但加移动成本/减速。
- 飞行：`altitude > 0` 忽略地面障碍；受禁飞区/室内限制；地面近战不能打空中。

### 8.3 战争迷雾

- 每格三态：`HIDDEN` / `EXPLORED` / `VISIBLE`。
- 可见性 5–10Hz 更新；网格 Bresenham + 高度/墙体遮挡；只更新玩家附近区块。
- 迷雾层：低分辨率可见度纹理（每区域或每区块）+ shader，在 world 之上、UI 之下。
- 已探索持久化；单位在不可见格隐藏；地形/建筑保留暗色轮廓。
- 性能：dirty rect 更新，不整图重算。

### 8.4 区块与寻路

```gdscript
# scripts/world/world_chunk.gd
class_name WorldChunk
extends Node2D

const SIZE := 64

var coord: Vector2i
var dirty: bool = false

func world_rect() -> Rect2i:
    return Rect2i(coord * SIZE, Vector2i(SIZE, SIZE))
```

```gdscript
var astar := AStarGrid2D.new()
astar.region = Rect2i(0, 0, 128, 128)
astar.cell_size = Vector2(32, 32)
astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
astar.update()

astar.set_point_solid(Vector2i(10, 10), true)
var path: Array[Vector2i] = astar.get_id_path(Vector2i(2, 2), Vector2i(20, 20))
```

规则：
- 地图变化时只更新受影响的格子，不要每次 `update()` 全图。
- 路径缓存 + 失败重试上限；不要每 tick 重算。
- 移动用 `NavigationAgent2D` 或简单的网格跟随；不要物理推挤。

---

## 9. AI 与工作系统

### 9.1 分层

```
需求（Needs） → 效用评分（Utility） → 工作（Job） → 执行器（Executor） → 行为（Move/Use/Wait）
```

- **Needs**：饥饿、疲劳、心情。每 tick 衰减，阈值触发。
- **Utility**：给每个可做的工作打分；选最高分；加随机扰动避免所有 Pawn 做同一件事。
- **JobBoard**：发布/认领/预约；防止两个 Pawn 抢同一个物品。
- **Executor**：状态机 `IDLE → MOVING → WORKING → DONE/FAILED`。
- **Behavior Tree**（可选）：复杂战斗/逃跑用 LimboAI 或 Beehave；日常需求用 utility 更简单。
- **具名 NPC vs cohort**：具名 NPC 个体跑 utility/日程；普通弟子按 cohort 聚合，靠近/相关时再提升为个体。
- **Action API**：玩家输入、脚本 AI、未来 LLM/AI 托管都输出同一种 action；系统校验后执行，AI 不直接改状态。
- **记忆/关系**：结构化表（事件、好感、亏欠、秘密、仇恨），不是 prompt 文本；LLM 只负责把表翻译成话。

### 9.2 工作生命周期

```gdscript
class_name Job
extends RefCounted

enum State { OPEN, CLAIMED, RUNNING, DONE, FAILED }

var id: int
var type: StringName          # "haul" / "chop" / "mine" / "build" / "cook"
var target_pos: Vector2i
var target_id: int = 0
var reserved_by: int = 0
var state: State = State.OPEN
var priority: float = 1.0
```

规则：
- 认领时原子设置 `reserved_by`；完成/失败必须释放。
- Pawn 死亡/眩晕/被征召时释放所有预约。
- 工作失败要有原因（目标消失、路径不可达、材料不足），写日志。
- 每 0.5–1 秒重新评估，不要每帧。

### 9.3 工作优先级

先做 **5×5 矩阵**：Pawn × 工作类型，0=不做，1=低，2=中，3=高，4=紧急。
不要一上来做 RimWorld 的完整优先级/技能/心情系统。

---

## 10. 战斗

- **实时 + 暂停**：空格暂停；速度 0/1/2/4；暂停时 UI/指令仍响应。
- **局部慢放**：每个 actor 有 `time_scale`；高阶技能让敌人 0.3、玩家 1.0；不用全局 `Engine.time_scale`。
- **规模**：玩家 + 3–5 同伴 vs 5–10 敌人；不做百人团战。
- **高度**：`altitude` 0/1/2；地面近战不能打空中；远程/对空技能可以；高度差影响射程/命中/视线；渲染用偏移 + 影子。
- **数据驱动**：武器/技能用 `Resource`；伤害公式集中在一个 `CombatMath`。
- **可读性**：攻击前摇、命中反馈、血条、威胁指示、地面范围指示、阵营颜色。
- **阵营**：`Faction` 资源；关系矩阵；友军伤害默认关闭。
- **Downed 状态**：死亡不是唯一结果；倒地/救援/俘虏为后续留口。
- **性能**：近战用 `Area2D` + 形状查询；远程用对象池；不要每帧 `intersect_shape` 全图。

```gdscript
# 伤害管线（示意）
func apply_damage(source: Node, target: Node, amount: int, type: StringName) -> void:
    var final := CombatMath.compute(amount, source, target, type)
    var health := target.get_node_or_null("HealthComponent") as HealthComponent
    if health:
        health.damage(final)
```

---

## 11. UI

- 所有 UI 用 `Control` + 容器；不要用绝对坐标堆。
- UI 放 `CanvasLayer`，与世界相机分离。
- HUD 只读状态；操作通过 signal/command 发给系统。
- 主题用 `Theme` 资源；颜色/字号集中管理。
- 支持键盘/鼠标；手柄和触屏后置。
- 分辨率：1280×720 基准，`canvas_items` 拉伸；UI 用锚点/容器适配。
- 本地化：所有玩家可见文本用 `tr()`；不要拼接句子。

---

## 12. 存档

### 12.1 格式

```json
{
  "version": 1,
  "saved_at": "2026-11-01T12:00:00",
  "seed": 123456,
  "clock": { "tick": 1234, "minute": 720 },
  "player": { "entity_id": 1, "position": [10.5, 20.0], "hp": 80 },
  "entities": [
    { "type": "pawn", "id": 2, "def": "pawn_cook", "position": [4, 5], "needs": {...} }
  ],
  "chunks": {
    "0,0": { "removed_tiles": [[3, 4]], "buildings": [...] }
  },
  "flags": { "tutorial_done": true },
  "quests": { "main_01": "active" }
}
```

### 12.2 规则

- **只存 deltas**：地形由 seed 重建，存档只存改动。
- **版本号 + 迁移函数**：`migrate_v1_to_v2(data)`。
- **原子写**：写 `.tmp` → flush → rename；保留 `.bak`。
- **不要存节点路径**；存实体 ID 和定义 ID。
- **不要存 Resource 对象**；存 ID/字典。
- **存档位置**：`user://saves/slot_01.json`；导出后 `res://` 只读。

```gdscript
const SAVE_VERSION := 1

func save_game(path: String = "user://saves/slot_01.json") -> Error:
    var data := {
        "version": SAVE_VERSION,
        "clock": GameClock.to_save_dict(),
        "player": GameState.player_to_dict(),
        "entities": EntityRegistry.to_save_array(),
        "flags": GameState.flags.duplicate(true),
    }
    var tmp := path + ".tmp"
    var file := FileAccess.open(tmp, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(JSON.stringify(data, "\t"))
    file.flush()
    file.close()
    var abs_tmp := ProjectSettings.globalize_path(tmp)
    var abs_dst := ProjectSettings.globalize_path(path)
    return DirAccess.rename_absolute(abs_tmp, abs_dst)
```

### 12.3 读档

- 先读 `version`，跑迁移链。
- 校验必填字段；损坏存档给出可读错误，不要崩溃。
- 读档后重建世界（seed）→ 应用 chunk deltas → 生成实体 → 绑定 UI。
- 读档过程中暂停模拟。

---

## 13. 性能预算

| 指标 | 目标 |
|---|---|
| 帧率 | 60 FPS（中端 PC，1920×1080） |
| 模拟 tick | < 8 ms（20 个 Pawn + 50 建筑） |
| 区块加载 | < 4 ms/帧（异步，每帧最多 1 个） |
| 实体数 | v0.1 < 100；v1 < 500 |
| 内存 | < 1 GB |
| Draw calls | < 500（2D） |
| 迷雾更新 | < 2 ms/次（5–10Hz，dirty rect） |

手段：
- `TileMapLayer` 而不是几千个 Sprite。
- 草地/装饰用 `MultiMeshInstance2D`。
- 屏幕外实体 `process_mode = PROCESS_MODE_DISABLED` 或降低 AI 频率。
- 对象池：投射物、伤害数字、掉落物。
- 避免在 `_process` 里 `get_nodes_in_group()` / `find_children()`。
- 路径缓存；A* 限制节点数。
- 世界生成/大块解析放 `WorkerThreadPool`。
- 用 Godot Profiler + `Performance` 单例实测，不猜。

---

## 14. 测试

### 14.1 金字塔

1. **纯逻辑单测**（最多）：伤害公式、需求衰减、工作评分、存档迁移、数据校验。
2. **场景集成测试**：生成一个小场景，跑 N 个 tick，断言状态。
3. **无头 smoke**：项目能导入、脚本能解析、主场景能实例化。
4. **截图/人工验收**：UI、动画、光照、可读性。

### 14.2 约定

- 测试文件放 `tests/cases/`，纯逻辑优先 `RefCounted`。
- 测试不依赖真实时间；手动调用 `tick()` 或注入 clock。
- 随机数用固定 seed。
- 测试失败输出：期望/实际/上下文。
- CI 跑 `python tools/godot.py check`。

---

## 15. 第三方依赖策略

优先级：
1. Godot 内置（TileMapLayer、AStarGrid2D、NavigationAgent2D、AnimationPlayer、Resource）。
2. 轻量、MIT、活跃维护的 addon。
3. 自己写 100–300 行能解决的事，不引入框架。

候选（按需，不要一次全装）：

| 需求 | 候选 | 备注 |
|---|---|---|
| 行为树 | LimboAI / Beehave | LimboAI 功能更全；Beehave 更轻 |
| 对话 | Dialogue Manager | 成熟、MIT |
| 相机 | Phantom Camera | 2D/3D 跟随、震屏、限制 |
| 测试 | GUT / 自带 headless runner | 先用自带，复杂后换 GUT |
| 格式化/Lint | gdtoolkit（gdformat/gdlint） | CI 必装 |
| 转向/群体 | Godot Steering AI Framework | 动物/人群 |

新增依赖必须记录到 `docs/DECISIONS.md`，并 pin 版本。

---

## 16. 已定与仍开放

已定（见 `docs/DECISIONS.md`）：
- 2D 等距 + 高度层（ADR-0013）。
- 实时 + 暂停 + 局部慢放（ADR-0017）。
- 512×512 首区、64×64 区块、5×5 加载（ADR-0015）。
- 单机模拟、脚本 AI 优先（ADR-0010 / 0018）。
- 数据包 + 世界生成管线（ADR-0019）。

仍开放（不阻塞 M1）：
- 等距 tile 最终尺寸（64×32 vs 32×16）——先用 64×32 占位。
- 相机缩放范围/边缘滚动速度——M1 调手感。
- 地图数据格式（JSON vs Resource vs 二进制）——M1 先用 JSON + seed，性能不够再换。
- 是否引入 LimboAI——先纯 utility/FSM，复杂战斗再评估。
- 具体境界名/数值——M2 前写设计文档。

这些在 M1 过程中用实测决定，不阻塞开工。
