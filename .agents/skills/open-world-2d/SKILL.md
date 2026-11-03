---
name: open-world-2d
description: Godot 4.7 的 2D 开放世界：区块流式加载、TileMapLayer、地图格式、程序生成、POI、河流/道路、导航、昼夜/天气、存档 deltas、性能。做大地图、世界生成、流式加载时使用。
---

# 2D 开放世界（Godot 4.7）

## 何时用

- 地图大于一屏，需要滚动/区块加载。
- 程序生成地形、生物群系、河流、道路、POI。
- 想从“单张手绘地图”升级到“可扩展世界”。
- 大地图卡顿、区块接缝、读档后地形不一致。

**不适用**：单屏关卡、纯 Roguelike 地牢（用 `procedural-gen` + `roguelike`）。

---

## 1. 先定世界规模

| 版本 | 规模 | 方式 |
|---|---|---|
| v0.1 | **128×128** | 单张地图，启动加载 |
| v1 | 512×512 | 区块 64×64，半径 2 加载 |
| v2 | 2048×2048 | 区块 + LOD + 异步生成 |
| 未来 | 无限 | 需要更强存档/流式/一致性，暂不做 |

**不要**一上来做无限世界。先把 128×128 跑顺。

---

## 2. 混合式世界：手工骨架 + 程序填充

纯程序生成容易“千篇一律”；纯手工内容量有限。推荐：

```
世界种子
  ├── 生物群系噪声（温度/湿度/高度）
  ├── 河流/湖泊（低洼 + 路径）
  ├── 道路（连接聚落/POI）
  ├── 手工 POI 模板（营地、遗迹、洞穴、村庄）
  └── 程序填充（树、石、草、装饰）
```

- **手工**：关键地标、主线地点、教学营地。
- **程序**：地形、植被、资源、随机 POI。
- **规则**：POI 之间有最小距离/可达性/生物群系约束。

---

## 3. 地图数据格式

### 3.1 小地图：ASCII + JSON 元数据

```
# 墙/建筑
. 地面
, 草地
T 树
~ 水
_ 木桥
P 玩家出生点
S 聚落中心
```

```json
{
  "width": 128,
  "height": 128,
  "tiles": "map_01.txt",
  "legend": { "#": "wall", ".": "ground", "T": "tree", "~": "water" },
  "pois": [
    { "id": "camp", "x": 64, "y": 64, "scene": "res://scenes/poi/camp.tscn" }
  ]
}
```

优点：可读、可 diff、可用 Python 工具生成/校验。
缺点：大图体积大；v1 可改二进制/压缩。

### 3.2 大地图：分块 JSON/二进制

```
data/world/
├── world.json          # seed, size, biome params
├── chunks/
│   ├── 0_0.json        # 只存 deltas（如果程序生成）
│   └── ...
└── pois.json
```

规则：
- 地形由 seed 重建；存档只存 **deltas**。
- 手工地图可以整块存，但要分块加载。
- 不要把所有 chunk 塞进一个巨大 JSON。

---

## 4. 区块设计

```gdscript
class_name WorldChunk
extends Node2D

const SIZE := 64

var coord: Vector2i
var ground: TileMapLayer
var walls: TileMapLayer
var props: TileMapLayer
var dirty: bool = false

func world_rect() -> Rect2i:
    return Rect2i(coord * SIZE, Vector2i(SIZE, SIZE))
```

### 4.1 每区块节点

```
Chunk (Node2D)
├── Ground (TileMapLayer)
├── Walls (TileMapLayer)
├── Props (TileMapLayer)
├── Entities (Node2D, y_sort_enabled = true)
└── Nav (NavigationRegion2D, optional)
```

- 每层一个 `TileMapLayer`；不要每格一个 Sprite。
- 实体（树/石头/建筑）用场景实例，不要塞进 TileMap。
- `Entities` 开 `y_sort_enabled`，让角色/树正确遮挡。

### 4.2 加载/卸载

```gdscript
const LOAD_RADIUS := 2
const UNLOAD_RADIUS := 3

var loaded: Dictionary[Vector2i, WorldChunk] = {}

func update_for(player_pos: Vector2) -> void:
    var center := world_to_chunk(player_pos)
    for y in range(center.y - LOAD_RADIUS, center.y + LOAD_RADIUS + 1):
        for x in range(center.x - LOAD_RADIUS, center.x + LOAD_RADIUS + 1):
            var c := Vector2i(x, y)
            if not loaded.has(c) and is_inside_world(c):
                _request_chunk(c)
    for c in loaded.keys():
        if abs(c.x - center.x) > UNLOAD_RADIUS or abs(c.y - center.y) > UNLOAD_RADIUS:
            _unload_chunk(c)
```

规则：
- 每帧最多加载 1 个区块；不要一次加载 25 个卡住。
- 卸载前保存 deltas；不要把未保存实体直接 `queue_free`。
- 玩家快速移动时，用加载队列 + 优先级（距离/方向）。
- 区块边界要重叠 1 格，避免接缝。
- 不要在 `_process` 里同步 `load()` 大场景；用 `ResourceLoader.load_threaded_request`。

---

## 5. 程序生成管线

### 5.1 噪声

```gdscript
func make_noise(seed_value: int, freq: float) -> FastNoiseLite:
    var n := FastNoiseLite.new()
    n.seed = seed_value
    n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    n.frequency = freq
    n.fractal_octaves = 4
    return n
```

- 高度/湿度/温度用不同 seed 偏移；不要共用同一个 noise。
- 频率：大地形 0.005–0.02；细节 0.05–0.1。
- 结果归一化到 0–1。
- 不要每格 `new FastNoiseLite()`；复用实例。

### 5.2 生物群系

```
if height < water_level: water
elif height < sand_level: beach
elif moisture > 0.6 and height < mountain: forest
elif height > mountain_level: mountain
else: grass
```

- 先 4–6 个群系；不要 20 个。
- 群系决定：地表 tile、树/石密度、可生成 POI、敌人。
- 群系边界用抖动/过渡，不要硬直线。

### 5.3 河流/道路

- 河流：从高处沿最低邻格走，直到水/边界；加宽 1–3 格。
- 道路：A* 连接聚落/POI，避开陡坡/水；桥/渡口。
- 河流/道路是**世界结构**，要在 chunk 生成前确定（或共享全局数据），否则接缝会断。

### 5.4 POI

```gdscript
class_name POIDef
extends Resource

@export var id: StringName
@export var scene: PackedScene
@export var biomes: Array[StringName] = []
@export var min_distance: int = 20
@export var weight: float = 1.0
@export var unique: bool = false
```

规则：
- POI 放置检查：群系、坡度、水源距离、与其他 POI 距离、可达性。
- 手工 POI 优先级高于随机 POI。
- 生成后记录到 `world.json`/deltas，不要每次进区块重新随机。
- 地牢入口/出口要连通；用 A* 验证。

### 5.5 装饰

- 树/石/草用小场景或 TileMapLayer；大量草用 `MultiMeshInstance2D`。
- 装饰不参与寻路（除非有碰撞）。
- 同一 seed 结果一致；不要用全局 `randf()`。

---

## 6. 确定性

```gdscript
var rng := RandomNumberGenerator.new()
rng.seed = hash(Vector2i(chunk.x, chunk.y)) ^ world_seed
var n := rng.randi_range(0, 100)
```

规则：
- 每个 chunk 用自己的 RNG；seed = world_seed + chunk 坐标 hash。
- 不要依赖全局 `randi()`；不要依赖节点顺序。
- 生成顺序固定：地形 → 水 → 道路 → POI → 装饰 → 实体。
- 浮点噪声在不同平台可能略有差异；存档不要依赖“完全相同的浮点结果”，只存 deltas。

---

## 7. 导航

### 7.1 网格（推荐先做）

- 全局 `AStarGrid2D` 128×128/512×512；或每 chunk 一个 + 跨区连接。
- 建筑/水/墙更新 solid。
- 修改后只更新局部；不要每帧 `update()` 全图。

### 7.2 NavigationRegion2D

- 每 chunk 一个 `NavigationRegion2D`，加载时 bake。
- 跨 chunk 连接：重叠 1–2 格；`NavigationLink2D` 处理门/桥。
- 烘焙放后台/加载时，不要卡帧。
- 动态障碍（建筑）用 `NavigationObstacle2D` 或重烘局部。

规则：
- 先做网格 A*；NavigationAgent2D 用于平滑移动。
- 路径失败要处理：目标不可达、跨 chunk 未加载、门锁。
- 不要在未加载的 chunk 上寻路。

---

## 8. 昼夜与天气

### 8.1 昼夜

- `GameClock` 提供 `hour`。
- `CanvasModulate.color` 随时间插值（夜蓝/黄昏橙）。
- 灯光 `PointLight2D`/`DirectionalLight2D`（2D）按时间开关。
- 不要把整个场景染成纯黑；保留可读性。

```gdscript
func _on_hour_changed(hour: int) -> void:
    var t := float(hour) / 24.0
    canvas_modulate.color = day_night_gradient.sample(t)
```

### 8.2 天气

- `GPUParticles2D` 雨/雪；`AudioStreamPlayer` 环境音。
- 天气影响：移动速度、视野、作物、心情。
- 先做视觉 + 1 个玩法影响；不要做完整气候模拟。

---

## 9. 存档 deltas

```json
{
  "seed": 123456,
  "chunks": {
    "0,0": {
      "removed_tiles": [[3, 4, "tree"]],
      "placed_tiles": [[5, 6, "wall"]],
      "buildings": [{ "def": "wall_wood", "cell": [5, 6], "hp": 100 }],
      "items": [{ "def": "wood", "cell": [7, 8], "count": 3 }]
    }
  },
  "discovered_pois": ["camp", "ruins_01"]
}
```

规则：
- 只存玩家改动/生成结果中不可重建的部分。
- 实体用 ID/def/位置/状态；不要存节点路径。
- 区块卸载时把 dirty 数据写入内存/存档。
- 读档：seed 重建 → 应用 deltas → 生成实体 → 恢复玩家。
- 版本号 + 迁移。

---

## 10. 性能

| 指标 | 目标 |
|---|---|
| 区块加载 | < 4ms/帧，异步 |
| 常驻区块 | 5×5 = 25（64×64） |
| Draw calls | < 500 |
| 内存 | < 1GB |
| 生成一个 chunk | < 10ms（后台线程） |

手段：
- `MultiMeshInstance2D` 草地/装饰。
- `VisibleOnScreenNotifier2D` 控制动画/粒子。
- 远处 chunk 降级：只保留地面/墙，不生成装饰/实体。
- `WorkerThreadPool` 生成地形数据；主线程只应用。
- 对象池：树/石头/掉落。
- 不要每帧扫描所有 chunk/实体。

---

## 11. 测试

### 地图校验
- [ ] 尺寸/legend 完整。
- [ ] 玩家出生点可达所有关键 POI（A*）。
- [ ] 没有孤岛/死路（除非设计）。
- [ ] 河流/道路连续，无接缝断裂。
- [ ] POI 不重叠/不悬空。

### 生成
- [ ] 同 seed 两次生成结果一致（至少 tile/POI 集合）。
- [ ] 不同 seed 有差异。
- [ ] 边界 chunk 不越界。
- [ ] 快速移动 10 个 chunk 不崩/不卡死。

### 存档
- [ ] 挖掉的树、建的墙、掉的物品，读档后一致。
- [ ] 未修改的 chunk 不写入存档（体积可控）。
- [ ] 读档后导航/碰撞正确。

---

## 12. 反模式

- ❌ 无限世界（没存档/性能方案）。
- ❌ 每格一个 Sprite/节点。
- ❌ 每个 chunk 一个巨大 `.tscn` 同步加载。
- ❌ 用全局 `randf()` 生成地形。
- ❌ 在 `_process` 里生成/加载 chunk。
- ❌ 只存“玩家位置”，不存世界改动。
- ❌ 河流/道路在每个 chunk 独立随机 → 接缝断裂。
- ❌ 未加载 chunk 上寻路。
- ❌ 20 个生物群系/100 种 POI 先于第一个可玩循环。

---

## 13. 相关技能

- `godot-tilemap` — TileMapLayer/TileSet/autotile
- `procedural-gen` — 噪声/地牢/种子
- `godot-sim-architecture` — 区块/存档/性能
- `level-design` — 手工地图/POI 布局
- `godot-verify` — 地图校验/测试
