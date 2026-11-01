---
name: colony-sim-systems
description: 设计/实现殖民模拟核心：Pawn 需求、心情、工作优先级、JobBoard、预约、储物区、建造蓝图、房间、生产、事件导演、袭击。做殖民者、基地、工作、库存、建造系统时使用。
---

# 殖民模拟系统（RimWorld/DF 风格）

## 何时用

- 做 Pawn 的饥饿/疲劳/心情。
- 做“谁去搬这堆木头”“谁去建墙”“谁去吃饭”。
- 做储物区、工作台、配方、房间、事件/袭击。
- 发现 Pawn 卡住、抖动、抢同一个物品、不干活。

**不适用**：纯 RPG 队伍、纯塔防、纯建造（无 Pawn）。那些用 `rpg`/`tower-defense`。

---

## 1. 先锁 MVP：3 个 Pawn，6 种工作

v0.1 只做：

| 系统 | MVP | 以后 |
|---|---|---|
| Pawn | 3 个 | 8–12 个 |
| 需求 | 饥饿、疲劳、心情 | 温度、社交、娱乐、成瘾 |
| 工作 | 搬运、砍树、采矿、建造、做饭、吃饭/睡觉 | 优先级矩阵、技能、品质 |
| 储物 | 1 个矩形区 + 过滤 | 多区、堆叠上限、冷藏 |
| 建筑 | 墙、床、工作台 | 门、防御、装饰、电力 |
| 生产 | 1 个配方 | 队列、品质、工作站 |
| 事件 | 1 次袭击 | 访客、贸易、疾病、天气 |
| 房间 | 不做 | 房间检测、美观、温度 |

**不要**一上来做完整 RimWorld。先把“3 个人能自己活过一晚”跑通。

---

## 2. Tick 顺序（很重要）

同一个 tick 内，按固定顺序执行，避免“谁先跑谁赢”：

```
1. GameClock.tick
2. 需求衰减（Pawn）
3. 心情/想法过期
4. 事件导演（低频）
5. 工作发布（建筑完成、资源出现）
6. Pawn 重新评估工作（低频，例如每 0.5s）
7. 工作执行（移动/使用/等待）
8. 战斗/伤害结算
9. 死亡/销毁清理
10. 视觉/UI 信号
```

规则：
- 需求先于决策；否则 Pawn 会饿死前一刻才找饭。
- 清理最后；不要让已死 Pawn 继续占工作。
- 低频系统用计数器，不要每 tick 跑。
- 不要在不同系统里各自 `_process` 改同一状态。

---

## 3. 数据模型

### 3.1 PawnDef

```gdscript
class_name PawnDef
extends Resource

@export var id: StringName
@export var display_name: String
@export var speed: float = 80.0
@export var max_hp: int = 100
@export var hunger_decay_per_hour: float = 4.0
@export var fatigue_decay_per_hour: float = 6.0
@export var work_priorities: Dictionary[StringName, int] = {}
```

### 3.2 NeedDef

```gdscript
class_name NeedDef
extends Resource

@export var id: StringName          # hunger / fatigue / mood
@export var max_value: float = 100.0
@export var decay_per_hour: float = 4.0
@export var critical_threshold: float = 20.0
```

### 3.3 JobDef

```gdscript
class_name JobDef
extends Resource

@export var id: StringName          # haul / chop / mine / build / cook
@export var display_name: String
@export var work_amount: float = 10.0
@export var required_tool: StringName = &""
@export var skill: StringName = &""
```

### 3.4 BuildingDef / ItemDef / RecipeDef

```gdscript
class_name BuildingDef
extends Resource
@export var id: StringName
@export var scene: PackedScene
@export var size: Vector2i = Vector2i.ONE
@export var build_cost: Dictionary[StringName, int] = {}
@export var work_amount: float = 10.0
@export var blocks_movement: bool = true
```

```gdscript
class_name RecipeDef
extends Resource
@export var id: StringName
@export var inputs: Dictionary[StringName, int] = {}
@export var outputs: Dictionary[StringName, int] = {}
@export var work_amount: float = 5.0
@export var station_tag: StringName = &""
```

---

## 4. 需求（Needs）

```gdscript
class_name NeedsComponent
extends Node

signal changed(need_id: StringName, value: float)

@export var defs: Array[NeedDef] = []

var values: Dictionary[StringName, float] = {}

func _ready() -> void:
    for d in defs:
        values[d.id] = d.max_value

func tick(hours: float) -> void:
    for d in defs:
        var v: float = values.get(d.id, d.max_value)
        v = maxf(v - d.decay_per_hour * hours, 0.0)
        values[d.id] = v
        changed.emit(d.id, v)

func is_critical(need_id: StringName) -> bool:
    var d := _def(need_id)
    return d != null and values.get(need_id, 0.0) <= d.critical_threshold
```

规则：
- 需求值 0–100；0 不是立即死亡，而是“严重惩罚/行为”。
- 饥饿：到 0 开始掉血/昏迷；不要直接秒杀。
- 疲劳：到 0 强制倒地睡觉；不要靠玩家微操。
- 心情：不是“血条”，是行为修正（工作效率/脾气/离开）。
- 每个需求都要有“恢复方式”，否则只是倒计时。

---

## 5. 效用评分（Utility）

```gdscript
func score_job(job: Job, pawn: Pawn) -> float:
    var score := job.priority
    # 距离惩罚
    var dist := pawn.global_position.distance_to(job.world_pos)
    score *= 1.0 / (1.0 + dist / 200.0)
    # 需求紧迫度
    if job.type == &"eat" and pawn.needs.is_critical(&"hunger"):
        score += 10.0
    if job.type == &"sleep" and pawn.needs.is_critical(&"fatigue"):
        score += 10.0
    # 随机扰动，避免所有 Pawn 同步
    score += randf_range(-0.05, 0.05)
    return score
```

规则：
- 分数 = 优先级 × 距离 × 需求 × 技能 × 随机扰动。
- 不要用 `if/elif` 硬编码所有组合；做成可加项。
- 记录“为什么选这个工作”（debug 面板），否则无法调。
- 每 0.5–1 秒评估一次，不要每 tick。

---

## 6. JobBoard 与预约

### 6.1 Job

```gdscript
class_name Job
extends RefCounted

enum State { OPEN, CLAIMED, RUNNING, DONE, FAILED }

var id: int
var type: StringName
var target_pos: Vector2i
var target_entity_id: int = 0
var priority: float = 1.0
var state: State = State.OPEN
var reserved_by: int = 0
var fail_reason: String = ""
```

### 6.2 JobBoard

```gdscript
extends Node

signal posted(job: Job)
signal completed(job: Job, pawn: Pawn)

var _jobs: Dictionary[int, Job] = {}
var _next_id: int = 1

func post(job: Job) -> void:
    job.id = _next_id
    _next_id += 1
    _jobs[job.id] = job
    posted.emit(job)

func claim(job_id: int, pawn_id: int) -> bool:
    var job: Job = _jobs.get(job_id)
    if job == null or job.state != Job.State.OPEN:
        return false
    job.state = Job.State.CLAIMED
    job.reserved_by = pawn_id
    return true

func complete(job_id: int, pawn: Pawn) -> void:
    var job: Job = _jobs.get(job_id)
    if job == null:
        return
    job.state = Job.State.DONE
    _jobs.erase(job_id)
    completed.emit(job, pawn)

func fail(job_id: int, reason: String) -> void:
    var job: Job = _jobs.get(job_id)
    if job == null:
        return
    job.state = Job.State.FAILED
    job.fail_reason = reason
    job.reserved_by = 0
    _jobs.erase(job_id)
```

规则：
- 认领必须原子；两个 Pawn 不能同时拿到。
- 完成/失败/死亡/眩晕/征召都要释放预约。
- 目标消失（树被砍、物品被拿走）→ 失败并重新发布。
- 每个 Job 要有超时/重试上限，防止永久卡住。
- 工作失败写日志/浮字，方便调试。

### 6.3 执行器

```gdscript
enum ExecState { IDLE, MOVING, WORKING, DONE }

func _on_tick(_i: int) -> void:
    match state:
        ExecState.IDLE:
            _pick_job()
        ExecState.MOVING:
            if _arrived():
                state = ExecState.WORKING
            else:
                _move_step()
        ExecState.WORKING:
            work_left -= 1.0 / GameClock.ticks_per_second
            if work_left <= 0.0:
                _finish_job()
```

规则：
- 移动用 `NavigationAgent2D` 或网格步进；不要物理推挤。
- 到达判定留容差；不要卡在 0.01 像素。
- 工作被打断（战斗/需求 critical）要保存进度或重做。
- 不要 `await` 长时间挂起；用状态机。

---

## 7. 工作优先级

先做 **5×6 矩阵**：

| Pawn \ 工作 | 搬运 | 砍树 | 采矿 | 建造 | 做饭 |
|---|---:|---:|---:|---:|---:|
| 厨师 | 2 | 1 | 1 | 2 | 4 |
| 建造工 | 2 | 2 | 2 | 4 | 1 |
| 杂工 | 3 | 3 | 3 | 2 | 2 |

- 0 = 不做；1 低；2 中；3 高；4 紧急。
- 先不做技能等级/品质/心情影响。
- UI 允许玩家改；保存到存档。
- 没有合适工作时，Pawn 闲逛/聊天/娱乐（后期）。

---

## 8. 储物区（Stockpile）

```gdscript
class_name Stockpile
extends Node2D

@export var area: Rect2i
@export var filter_tags: Array[StringName] = []

var _stacks: Dictionary[StringName, int] = {}
var _reserved: Dictionary[StringName, int] = {}

func can_accept(item_id: StringName) -> bool:
    return filter_tags.is_empty() or item_id in filter_tags

func reserve(item_id: StringName, amount: int) -> bool:
    var free := _stacks.get(item_id, 0) - _reserved.get(item_id, 0)
    return free >= amount
```

规则：
- 先做“区域 + 过滤 + 总量”，不要做每个格子的堆叠上限。
- 搬运 Job 要预约目标格/物品，避免两个 Pawn 搬同一堆。
- 物品进入储物区才“安全”；地上物品会腐烂/被偷（后期）。
- 储物区可视化（半透明色块 + 过滤图标）。

---

## 9. 建造

### 9.1 流程

```
玩家放置蓝图 → 检查材料 → 生成 build Job → Pawn 认领
→ 搬材料 → 施工（work_amount）→ 完成 → 替换为建筑实例
```

### 9.2 蓝图

```gdscript
class_name BuildingBlueprint
extends Node2D

var def: BuildingDef
var cell: Vector2i
var delivered: Dictionary[StringName, int] = {}
var work_left: float = 0.0
var reserved_by: int = 0
```

规则：
- 放置时检查：地形可建、无重叠、材料够、可达。
- 取消返还已交付材料（或掉地上）。
- 建造中可被攻击/取消；保存进度。
- 完成时发 `building_completed`，更新导航/房间/储物。
- 墙/门要更新 AStarGrid2D 的 solid；不要只改视觉。

---

## 10. 房间（后期）

- 用 flood fill 从门/边界找封闭区域。
- 房间属性：面积、地板类型、家具、温度、美观。
- 先不做；MVP 只需要“床属于谁”“工作台在哪”。
- 房间检测每 2–5 秒一次，不要每 tick。

---

## 11. 心情（后期）

- 心情 = 基础值 + 想法总和。
- 想法：饿了、睡地板、漂亮房间、同伴死亡、雨淋。
- 每个想法有 `stack`, `duration`, `mood_delta`。
- 阈值：崩溃/暴怒/离开；不要做 20 种心理疾病。
- 先做 3–5 个想法；玩家能看懂“为什么心情低”。

---

## 12. 事件导演（Storyteller）

v0.1 只做：

```
每游戏小时检查：
  threat_budget += 1
  如果 day >= 2 且 threat_budget >= 10 且没有袭击：
    生成 1 次袭击
    threat_budget = 0
```

规则：
- 事件有冷却/预算，不要纯随机。
- 袭击强度随天数/财富增长，但设上限。
- 事件前给玩家预警（声音/文字/边缘箭头）。
- 失败要产生故事（受伤/建筑损坏/被抢），不要只读档。
- 后期再做访客/贸易/疾病/天气。

---

## 13. 战斗（与殖民 sim 的接口）

- Pawn 有 `HealthComponent`、`Faction`、`CombatController`。
- 征召：玩家选中 Pawn → 右键目标 → 移动到射程 → 攻击。
- 非征召：遇到威胁 → 逃跑/呼救/反击（按性格/装备）。
- 倒地/死亡：释放工作预约；尸体/掉落物；心情影响。
- 不要做复杂部位/疼痛/感染；MVP 只做 HP + 倒地。

---

## 14. 寻路

- 网格：`AStarGrid2D`；建筑/墙更新 solid。
- 连续：`NavigationAgent2D`；区域烘焙。
- 路径失败：
  - 目标不可达 → 工作失败，释放预约。
  - 路径被堵 → 重算 1–2 次，然后放弃。
  - 门/桥 → 单独处理通行成本。
- 不要每帧重算；不要所有 Pawn 同一帧重算（错开）。

---

## 15. 存档要点

- Pawn：ID、def、位置、HP、需求、心情想法、工作优先级、当前 Job ID。
- Job：ID、类型、目标、预约者、进度；或读档后重建（更简单）。
- 建筑：def、cell、完成状态、库存、工作进度。
- 储物：区域、过滤、物品总量。
- 世界：seed、chunk deltas、已发现 POI。
- 事件导演：预算、冷却、下一次袭击天数。
- **读档后重建 JobBoard** 往往比存每个 Job 更稳；先存“目标状态”，再重新发布工作。

---

## 16. 测试场景（必须）

- [ ] 饥饿 Pawn 会自动找食物；没有食物会饿到掉血/倒地。
- [ ] 疲劳 Pawn 会自动找床；没有床会睡地上。
- [ ] 两个 Pawn 不会搬同一堆木头。
- [ ] 目标物品被拿走 → 搬运 Job 失败并释放。
- [ ] 建造材料不足 → 不生成/不完成，给出提示。
- [ ] 墙建成后 A* 不再穿墙。
- [ ] Pawn 死亡 → 释放所有预约；工作重新可认领。
- [ ] 存档 → 读档 → 需求/建筑/物品/时间一致。
- [ ] 10 分钟不干预，3 个 Pawn 不卡死/不抖动。
- [ ] 12 Pawn + 50 建筑，tick < 8ms。

---

## 17. 范围守卫

出现以下想法，先写进 backlog：

- 温度/气体/流体模拟。
- 每个物品单独耐久/品质/材质。
- 完整身体部位/疼痛/感染。
- 20 种心情/心理疾病。
- 50 种工作/技能树。
- 多楼层/电梯/电力/水管。
- 50 个 Pawn 的完整模拟。

**先问：玩家会因此做什么新决策？** 答不上来就不做。

---

## 18. 反模式

- ❌ 每个 Pawn 在 `_process` 里自己找工作。
- ❌ 工作不预约，两个 Pawn 抢同一物品。
- ❌ 工作失败不释放预约，永久卡死。
- ❌ 需求/工作/移动全在一个脚本。
- ❌ 用 `await` 做工作流程，无法存档/中断。
- ❌ 每 tick 全图 A*。
- ❌ 把“显示名”当 ID 存档。
- ❌ UI 直接改 Pawn 状态，绕过系统。
- ❌ 先做 20 种工作，再做第一个可玩循环。

---

## 19. 相关技能

- `godot-sim-architecture` — tick/实体/存档/性能
- `game-ai` — FSM/BT/steering
- `ai-behavior-trees-utility-ai` — 效用/行为树实现
- `godot-2d-movement` — CharacterBody2D/寻路移动
- `save-systems` — 存档模式
- `godot-verify` — 测试/验收
