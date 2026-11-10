# 给 Unity 开发者的 Godot 4.7 速成

> 研究资料：记录来源与适用限制，不授予引入依赖或改变规则的权限。

> 你不需要“重新学编程”，只需要换一套**心智模型**。
> 本文只讲和 Unity 不一样、且做本项目会用到的部分。

本文是Godot 4.7通用入门示例，并非Reol现有 `Node` 层级或已实现功能；运行所有者、共同时间、数据目录和实际版本以[项目架构](../../docs/engineering/architecture.md)、[当前构建](../../docs/status/baseline.md)和真实代码为准。游戏引擎持续跟进最新稳定版，API随采用版本核查。

---

## 1. 最重要的三个心智转变

### 1.1 Godot Scene 使用 Node，组合优于深继承

Unity：`GameObject` + 一堆 `Component`。
Godot：场景用`Node`树，每个`Node`可以挂脚本，子`Node`是常见的组合方式。非场景规则和数据也可以是`RefCounted`或`Resource`；本项目按已有模拟/运行/持久化边界选择。

```
Player (CharacterBody2D)
├── Sprite2D
├── CollisionShape2D
├── HealthComponent (Node)
├── InventoryComponent (Node)
└── Camera2D
```

- Godot Scene 可保存为 `.tscn`，加载为 `PackedScene` 后实例化；不需要把 Unity `Prefab` 与 `Component` 当成 Godot 的内置类型。
- 脚本 `extends Node2D` / `CharacterBody2D`，直接成为该 `Node` 的行为。
- 组合：把能力做成子 `Node` 或 `Resource`，不要写 10 层继承。

### 1.2 Godot Scene 的用途对应 Unity Scene 或 Prefab

- `.tscn` 可以是整个关卡，也可以是一个敌人、一个 UI 面板、一个子弹。
- `PackedScene` 是可实例化的 `Resource`，可用于整个场景或可复用的 `Node` 组合。
- `PackedScene.instantiate()` + `add_child()` ≈ `Instantiate()`。
- Scene 可以嵌套；Godot Inherited Scene 可用于制作场景变体，Unity 的对应用途是 Prefab Variant。
- 运行中的 `Node.get_tree()` 返回 `SceneTree`；查看编辑器中打开的 Scene 层级时，以实际 `Node` 层级为准。

### 1.3 signal 是内置的事件系统

```gdscript
signal health_changed(current: int, maximum: int)

func take_damage(amount: int) -> void:
    health = maxi(health - amount, 0)
    health_changed.emit(health, max_hp)
```

```gdscript
health_changed.connect(_on_health_changed)
# 或带参数绑定
health_changed.connect(_on_health_changed.bind(self))
```

- 比 UnityEvent 更轻、类型更安全。
- `Node` 释放时连接自动断开。
- 跨系统解耦优先用 signal，不要到处 `GetComponent`。

---

## 2. Unity → Godot 对照表

| Unity | Godot 4.7 | 备注 |
|---|---|---|
| `GameObject` | `Node` | 一切基础 |
| `Component` | 子 `Node` 或脚本 | 组合 |
| `MonoBehaviour` | `extends Node` 的脚本 | 脚本就是组件 |
| `Prefab` | `.tscn` / `PackedScene` | 可实例化 |
| `Scene` | `.tscn` | 同一个概念 |
| `Transform` | `Node2D` / `Node3D` | 2D 用 Node2D |
| `Vector3` | `Vector2` / `Vector3` | 2D 用 Vector2 |
| `Start()` | `_ready()` | 子 `Node` 已就绪 |
| `Awake()` | `_init()` / `_enter_tree()` | `_init` 最早 |
| `Update()` | `_process(delta)` | 每渲染帧 |
| `FixedUpdate()` | `_physics_process(delta)` | 固定物理 tick |
| `OnDestroy()` | `_exit_tree()` | 离开树 |
| `[SerializeField]` | `@export` | Inspector 可编辑 |
| `GetComponent<T>()` | `$Node` / `get_node()` / `@onready` | 类型转换 |
| `Instantiate(prefab)` | `packed.instantiate()` + `add_child()` | 别忘了 add_child |
| `Destroy(obj)` | `queue_free()` | 延迟释放 |
| `UnityEvent` | `signal` | 类型化 |
| `ScriptableObject` | `Resource` | `.tres` |
| Singleton 模式 | autoload | Project Settings → Autoload；按需选择实例和状态所有者 |
| `SceneManager.LoadScene` | `get_tree().change_scene_to_file()` | 或 `change_scene_to_packed` |
| `DontDestroyOnLoad` | autoload | 全局 `Node` |
| `Coroutine` | `await` | `await get_tree().create_timer(1.0).timeout` |
| `Time.deltaTime` | `delta` 参数 | 不要自己算 |
| `Time.timeScale` | `Engine.time_scale` | 慎用；模拟用自定义 speed |
| `Input.GetAxis` | `Input.get_axis()` | 需要 InputMap |
| `Input.GetButtonDown` | `Input.is_action_just_pressed()` | 动作名 |
| `Physics.Raycast` | `RayCast2D` / `direct_space_state` | 2D |
| `OnTriggerEnter` | `Area2D.body_entered` | signal |
| `Rigidbody` | `RigidBody2D` | 物理驱动 |
| `CharacterController` | `CharacterBody2D` | 推荐玩家/NPC |
| `BoxCollider` | `CollisionShape2D` + `RectangleShape2D` | 形状是资源 |
| `Tilemap` | `TileMapLayer` | 4.3+ 新 `Node` |
| `Animator` | `AnimationPlayer` / `AnimationTree` | 状态过渡可用 `AnimationTree` |
| `Canvas` | `Control` | UI |
| `RectTransform` | anchors + containers | 不要绝对定位 |
| `Image` | `TextureRect` | |
| `Text` | `Label` / `RichTextLabel` | |
| `ScrollView` | `ScrollContainer` | |
| `HorizontalLayoutGroup` | `HBoxContainer` | |
| `VerticalLayoutGroup` | `VBoxContainer` | |
| `GridLayoutGroup` | `GridContainer` | |
| `Sorting Layer` | `z_index` + `y_sort_enabled` | 2D 俯视常用 Y-sort |
| `SpriteRenderer` | `Sprite2D` | |
| `Sprite Atlas` | `AtlasTexture` / `Sprite2D.region` | |
| `ParticleSystem` | `GPUParticles2D` / `CPUParticles2D` | |
| `AudioSource` | `AudioStreamPlayer2D` | |
| `AudioMixer` | `AudioBus` | |
| `PlayerPrefs` | `ConfigFile` / JSON in `user://` | |
| `Debug.Log` | `print()` | `push_error` 到错误面板 |
| `Gizmos` | `_draw()` / debug draw | |
| `NavMesh` | `NavigationRegion2D` / `NavigationAgent2D` | 2D |
| `Terrain` | `TileMapLayer` | |
| `Light` | `Light2D` / `CanvasModulate` | 2D |
| `Cinemachine` | Phantom Camera（插件） | 可选 |
| `TextMeshPro` | `Label` + 字体资源 | |
| `Localization` | `tr()` + CSV/PO | |
| `Addressables` | `ResourceLoader.load_threaded_request` | |
| `AssetBundle` | `.pck` / 导出预设 | |
| `Tags` | groups | |
| `Layers` | collision layers/masks | 项目设置里命名 |
| `Prefab Variant` | Inherited Scene | |

---

## 3. GDScript 速览（只列会用的）

```gdscript
extends CharacterBody2D
class_name Player                 # 注册全局类型

signal died

@export var speed: float = 220.0
@export_range(0, 100) var hp: int = 100
@export var bullet_scene: PackedScene

@onready var sprite: Sprite2D = $Sprite2D
@onready var label: Label = %Label   # 场景唯一名

var _velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
    # 子 Node 已就绪；连接 signal
    died.connect(_on_died)

func _physics_process(delta: float) -> void:
    var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    velocity = dir * speed
    move_and_slide()

func take_damage(amount: int) -> void:
    hp = maxi(hp - amount, 0)
    if hp == 0:
        died.emit()

func _on_died() -> void:
    queue_free()
```

要点：
- `:=` 推断类型；`:` 显式类型。
- `@onready` 在 `_ready` 前解析；不要在 `_init` 里 `$Node`。
- `%Name` 是场景唯一名，比长路径稳。
- `class_name` 会进全局缓存；新增后需要导入一次。
- `await` 可以等待 signal 或另一个异步函数；不要无限等，加超时。
- `@tool` 让脚本在编辑器里运行；慎用。

---

## 4. 2D 特有的坑

### 4.1 Y 轴向下

Unity 2D 的世界坐标通常 Y 向上，Godot 2D 默认 Y 向下；从 Unity 移植坐标或动画时须核对。
`Vector2(0, -1)` 是向上。

### 4.2 角度

- `rotation` 是**弧度**。
- `rotation_degrees` 是角度。
- `Vector2.angle()` 返回弧度；`angle_to()`。

### 4.3 像素风设置

- 纹理导入：Filter = Nearest，Mipmaps = Off。
- 项目设置：`rendering/textures/canvas_textures/default_texture_filter = Nearest`。
- Camera2D：`position_smoothing_enabled` 慎用（像素抖动）；需要时开 `pixel_snap`。
- 不要把 `Sprite2D` 放在半像素位置。

### 4.4 Y-sort（俯视遮挡）

```gdscript
# 父 Node（例如 World/Entities）
y_sort_enabled = true
```

子 `Node` 按 `global_position.y` 排序；脚在下方的前景会盖住上方。
不要再用 Unity 的 Sorting Layer 思路；`z_index` 只做全局层级（UI、地面、特效）。

### 4.5 TileMapLayer

- Godot 4.3+ 用 `TileMapLayer`，不是旧 `TileMap`。
- 每个 layer 一个 `Node`：ground / walls / props。
- TileSet 里配置碰撞层、导航层、terrain。
- `set_cell(coords, source_id, atlas_coords)`。
- 大地图不要几千个 Sprite；用 TileMapLayer。

---

## 5. PackedScene 与 Resource

### 5.1 实例化

```gdscript
@export var enemy_scene: PackedScene

func spawn_enemy(pos: Vector2) -> void:
    var enemy := enemy_scene.instantiate()
    enemy.global_position = pos
    add_child(enemy)
```

- 实例化后必须 `add_child()` 才进树。
- 如果要保存进场景，设置 `owner`；运行时生成的不需要。
- `queue_free()` 是延迟释放；不要立刻再用。

### 5.2 Resource ≈ ScriptableObject

```gdscript
class_name ItemDef
extends Resource

@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export var max_stack: int = 99
```

- 存成 `.tres`，可在 Inspector 编辑。
- **Resource 默认共享**；每个实例要独立数据时 `duplicate()`。
- 不要把运行时状态写进共享的 Def 资源。

### 5.3 preload vs load

- `preload("res://...")`：编译期加载，路径必须常量；循环引用会炸。
- `load("res://...")`：运行时加载；适合可选/大资源。
- 大场景用 `ResourceLoader.load_threaded_request()`。

---

## 6. UI

- UI 根用 `CanvasLayer`，不要跟世界相机一起缩放。
- 用 `Control` + 容器（`VBoxContainer`、`HBoxContainer`、`GridContainer`、`MarginContainer`）。
- 锚点：`set_anchors_preset(Control.PRESET_FULL_RECT)`。
- 尺寸：`size_flags_horizontal = Control.SIZE_EXPAND_FILL`。
- 主题：`Theme` 资源统一样式；不要在每個 Label 上改颜色。
- 本地化：`tr("KEY")`；不要拼接句子。
- 暂停菜单：`process_mode = Node.PROCESS_MODE_ALWAYS`；世界的 `Node` 暂停。

```gdscript
# 暂停
get_tree().paused = true

# 暂停菜单仍响应
pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
```

---

## 7. 输入

```gdscript
# 在项目设置 Input Map 里定义动作
var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
var attack := Input.is_action_just_pressed("attack")
```

- 不要硬编码 `KEY_W`；用动作名，方便改键/手柄。
- `Input.get_vector` 自带死区/归一化。
- 鼠标：`get_global_mouse_position()`。
- 手柄/触屏后置；先把键鼠做顺。

---

## 8. 物理与碰撞

| 需求 | `Node` |
|---|---|
| 玩家/NPC 移动 | `CharacterBody2D` + `move_and_slide()` |
| 受重力/推挤的物体 | `RigidBody2D` |
| 静态墙/地形 | `StaticBody2D` 或 TileMapLayer 碰撞 |
| 触发区/交互区 | `Area2D` |
| 射线检测 | `RayCast2D` |
| 形状检测 | `ShapeCast2D` |

- 碰撞层/掩码在 Project Settings → Layer Names → 2D Physics 命名。
- `CollisionShape2D` 的 shape 是资源；多个实例共享时注意 `duplicate()`。
- `Area2D` 的 `monitoring` / `monitorable` 决定是否检测。
- 不要用 `RigidBody2D` 做玩家；用 `CharacterBody2D`。

---

## 9. 导航与寻路

- 小地图/网格：`AStarGrid2D`，简单、可控、适合殖民 sim。
- 大地图/连续空间：`NavigationRegion2D` + `NavigationAgent2D`。
- `NavigationAgent2D` 需要区域烘焙；`target_position` 设置目标；`get_next_path_position()` 取下一个点。
- 网格寻路失败要处理：目标不可达、路径被建筑堵住、重新规划。
- 不要每帧重算路径。

---

## 10. 存档与文件

- `user://` 是可写目录；`res://` 导出后只读。
- `OS.get_user_data_dir()` 查看实际路径。
- `FileAccess` 读写文件；`DirAccess` 目录操作。
- `JSON.stringify` / `JSON.parse_string`。
- 原子写：写 `.tmp` → flush → rename。
- 存档要版本号 + 迁移；不要直接存 `Node` 路径。

```gdscript
var file := FileAccess.open("user://save.json", FileAccess.WRITE)
if file:
    file.store_string(JSON.stringify(data, "\t"))
    file.close()
```

---

## 11. 调试

- `print()` → 输出面板。
- `push_error()` / `push_warning()` → 错误/警告面板，带堆栈。
- `breakpoint` 关键字 / 编辑器断点。
- `assert(condition)` 只在 debug 生效；不要用于玩家输入校验。
- 远程调试：编辑器运行游戏时自动连接；`Debugger` 面板看堆栈/性能。
- `Performance.get_monitor(Performance.TIME_FPS)` 看帧率。
- `Engine.get_frames_per_second()`。
- 可视化调试：`_draw()` 画线/圆；`draw_string`；`DebugDraw` 插件可选。

---

## 12. 常见崩溃/坑

| 现象 | 原因 | 解决 |
|---|---|---|
| `Identifier "X" not declared` | 新 `class_name` 没导入 / 循环引用 | 运行 `--import`；拆分循环 |
| `Invalid get index 'x'` | `Node` 路径错 / 还没进树 | 用 `@onready`、`get_node_or_null` |
| signal 连了没反应 | 连接在 `_ready` 前 / 对象已释放 | 检查生命周期；`is_instance_valid` |
| `queue_free()` 后还用 | 延迟释放 | 先置空引用；用 `is_instance_valid` |
| 场景实例化后不显示 | 忘了 `add_child` | 加进树 |
| UI 不缩放 | 锚点/容器没设 | 用 anchors + size flags |
| 像素画模糊 | 纹理 Filter 线性 | 改 Nearest |
| 角色抖动 | 相机平滑 + 半像素 | 关平滑 / pixel snap |
| 暂停后 UI 不响应 | `process_mode` | 设 `PROCESS_MODE_ALWAYS` |
| 导出后存档失败 | 写了 `res://` | 改 `user://` |
| 读档后引用失效 | 存了 `Node` 路径 | 存实体 ID |
| 性能差 | 每帧 `get_nodes_in_group` / `load` | 缓存、signal、对象池 |

---

## 13. 建议学习顺序

1. **官方 Getting Started**（2D 部分）：https://docs.godotengine.org/en/4.7/getting_started/step_by_step/index.html
2. **GDScript 风格指南**：https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html
3. **2D 移动**：`CharacterBody2D` + `move_and_slide`
4. **TileMapLayer**：做一张可走的地图
5. **signal**：把 UI 和游戏逻辑分开
6. **Resource**：做 ItemDef/BuildingDef
7. **Save/Load**：JSON + `user://`
8. **Navigation**：AStarGrid2D / NavigationAgent2D
9. **AnimationPlayer**：角色动画
10. **Control/Theme**：HUD 和菜单

然后直接做 `docs/plans/roadmap.md` 的 M1。不要先看 50 小时教程。

---

## 14. 和 Unity 最大的不同（一句话总结）

Unity 你是在**搭 GameObject + 写 Component**；
Godot 你是在**种一棵 Node 树 + 用 signal 连接**。
把 `Node` 树当成你的架构图，事情就顺了。
