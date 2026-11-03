---
name: godot-verify
description: Godot 4.7 项目的验证流程：无头导入/测试、运行、读日志、截图、常见报错、完成定义。改完代码/场景后必须使用；不要把“应该能跑”当完成。
---

# Godot 验证流程（4.7）

## 核心原则

**没有命令输出、日志或截图，就不算完成。**
AI 最常见的失败不是不会写，而是“写完就宣布成功”。这个技能就是防这个。

---

## 1. 验证阶梯

从便宜到贵，逐层往上：

```
1. 静态：脚本能解析（load 成功）
2. 导入：资源/class_name 能导入
3. 单测：纯逻辑断言
4. 运行：主场景/目标场景能启动 N 帧
5. 交互：输入/工作/战斗流程
6. 视觉：截图检查 UI/动画/可读性
7. 性能：Profiler/FPS
```

不需要每次都跑满；但**至少跑到与改动匹配的层级**。

| 改动 | 最低验证 |
|---|---|
| 纯函数/数据 | 单测 |
| 新脚本 | 解析 + 单测/运行 |
| 新场景/节点 | 实例化 + 运行截图 |
| UI | 截图（1280×720） |
| 存档 | roundtrip |
| 性能相关 | Profiler/FPS |
| 修 bug | 复现步骤 + 修复后同步骤 |

---

## 2. 命令

先确保 Godot 可执行：

```bash
python tools/godot.py doctor
python tools/godot.py version
```

### 2.1 导入

```bash
python tools/godot.py import
```

何时跑：
- 新增/重命名资源、TileSet、字体、场景。
- 新增 `class_name` 后出现 “Identifier not declared”。
- 从 git 拉取后第一次。

### 2.2 测试

```bash
python tools/godot.py test
```

内部执行：

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

测试脚本会：
- 校验 `project.godot` 的 4.7 特性。
- 校验主场景存在且能实例化。
- 递归 `load()` `scripts/`、`tests/` 下的 `.gd`。
- 运行所有 `test_*` 方法，失败退出码 1。

### 2.3 导入 + 测试

```bash
python tools/godot.py check
```

**这是提交前的最低门槛。**

### 2.4 运行

```bash
python tools/godot.py run
python tools/godot.py run --headless --quit-after 120
```

- `--headless`：无窗口；适合 CI/smoke。
- `--quit-after 120`：跑 120 帧后退出；适合“能不能启动”。
- 运行日志看终端输出；`tools/godot.py` 会 tee 到 `logs/`。

### 2.5 编辑器

```bash
python tools/godot.py editor
```

需要看场景/手动验证时用。AI 优先用 Godot AI MCP 操作已打开的编辑器。

### 2.6 导出

```bash
python tools/godot.py export --preset "Windows Desktop" --output build/windows/reol.exe
```

需要先安装导出模板。

---

## 3. 测试怎么写

### 3.1 纯逻辑优先

```gdscript
func test_hunger_decays() -> void:
    var needs := NeedsComponent.new()
    needs.hunger = 100.0
    needs.tick(1.0)
    assert_eq(needs.hunger, 96.0, "hunger after 1h")
```

- 不依赖真实时间；手动 `tick()`。
- 不依赖全局随机；固定 seed。
- 不依赖场景树；纯 `RefCounted`/`Resource`。
- 一个测试一个行为。
- 失败输出期望/实际/上下文。

### 3.2 场景/集成

```gdscript
func test_boot_scene_instantiates() -> void:
    var packed: PackedScene = load("res://scenes/boot.tscn")
    assert_true(packed != null, "boot.tscn loads")
    var node := packed.instantiate()
    assert_eq(node.name, "Boot", "root name")
    node.free()
```

- 用 `free()` 而不是 `queue_free()`，避免测试结束还有节点。
- 需要帧的测试：`await process_frame` + 超时；不要无限等。
- 不要依赖主场景自动加载；测试自己实例化。

### 3.3 测试命名

- 文件/方法：`test_<system>_<behavior>`。
- 例：`test_jobboard_claim_is_atomic`、`test_save_roundtrip`。
- 一个失败只指向一个行为。

---

## 4. 读错误

Godot 输出通常长这样：

```
SCRIPT ERROR: Parse Error: Expected ")" ...
          at: GDScript::reload (res://scripts/foo.gd:12)
ERROR: Failed to load resource 'res://scripts/foo.gd'.
```

**只看第一条红色/SCRIPT ERROR。** 后面的常常是级联。

| 错误 | 常见原因 | 处理 |
|---|---|---|
| `Identifier "X" not declared in the current scope` | 新 `class_name` 没导入 / 循环 preload | `import`；拆循环 |
| `Parse Error: Expected ...` | 语法/缩进/括号 | 看行号；格式化 |
| `Invalid call. Nonexistent function 'x'` | API 版本不对/拼写 | 查 4.7 文档/context7 |
| `Invalid get index 'x' (on base: 'null instance')` | 节点不存在/未进树 | `@onready`/`get_node_or_null` |
| `Node not found: "..."` | 路径错/场景改结构 | 用 `%UniqueName` 或 `@export` |
| `Failed to load resource` / `No loader found` | 没导入/路径错 | `import`；检查路径 |
| `Class "X" hides a global script class` | `class_name` 重复 | 重命名 |
| `Cyclic reference` | A preload B，B preload A | 运行时 `load()`/提取公共类 |
| `Signal 'x' is already connected` | 重复 connect | 先 `is_connected` |
| `Can't open file 'user://...'` | 目录不存在 | `DirAccess.make_dir_recursive_absolute` |
| `Can't open file 'res://...'`（导出后） | `res://` 只读 | 写 `user://` |
| `Condition "!is_inside_tree()"` | 未 `add_child` 就操作 | 先入树 |
| `Attempt to call function ... in base 'null instance'` | 对象已释放/未初始化 | `is_instance_valid` |
| `Invalid UID` / `UID duplicate` | 手改 `.tscn`/重命名 | 用编辑器修复；不要手写 UID |

如果错误里带 `at: ...:line`，直接跳到那一行；不要从文件头读。

---

## 5. 调试流程

```
1. 复现：最小步骤/最小场景。
2. 读第一条错误，定位文件/行。
3. 加 print/断点，确认状态（不是猜）。
4. 二分：注释一半/回滚一半，缩小范围。
5. 查文档：4.7 API 是否变了。
6. 修一个，跑一次 check。
7. 写回归测试，防止再犯。
```

不要：
- 一次改 10 个地方。
- 把 `push_error` 当异常处理。
- 用 `assert` 校验玩家输入。
- 忽略警告（尤其 `UNUSED_SIGNAL`、`SHADOWED_VARIABLE`）。

---

## 6. 视觉验证

涉及画面时，必须看：

- 用 Godot AI `editor_screenshot`（game/2D viewport）或运行游戏截图。
- 分辨率 1280×720；检查 UI 锚点/文字溢出。
- 检查：
  - [ ] 文字不重叠、不出屏、不被遮挡。
  - [ ] 颜色对比够（尤其夜晚/选中态）。
  - [ ] 层级正确（Y-sort、z_index）。
  - [ ] 像素不模糊（Nearest）。
  - [ ] 动画不抖/不滑步。
- 截图存 `artifacts/qa/`（临时）；里程碑截图复制到 `docs/qa/`。
- 对比改动前/后；不要只看“能跑”。

---

## 7. 用 MCP 验证（Godot AI）

```
1. editor_state            # 编辑器版本/当前场景/是否在运行
2. scene_get_hierarchy     # 看节点结构
3. node_get_properties     # 看关键属性
4. project_run             # 跑游戏，等 game_status
5. logs_read(source="editor"|"game", include_details=true)
6. editor_screenshot       # 看画面
7. test_run / test_manage(results_get)  # 跑编辑器内测试
```

规则：
- 写入后看返回的 `diagnostics`（headless 下这是可靠通道）。
- `project_run` 之后必须看 `game_status`；`not_live`/`break` 不是成功。
- 不要只信 `is_playing`。
- 截图/日志是证据；不要只信工具返回的 “ok”。

---

## 8. 性能验证

- `Performance.get_monitor(Performance.TIME_FPS)` / `Engine.get_frames_per_second()`。
- Godot Profiler：看脚本/物理/绘制哪一块超。
- 目标：60 FPS；sim tick < 8ms；chunk load < 4ms。
- 在“最坏情况”测：12 Pawn + 100 建筑 + 夜间 + 粒子。
- 不要用“我电脑很快”当结论。

---

## 9. 完成定义（DoD）

- [ ] 行为符合验收标准；边界情况处理。
- [ ] 新代码有类型；没有新增错误/警告（或记录原因）。
- [ ] 数值在 `data/`，没有魔法数字。
- [ ] 有测试，或说明为什么不适合自动化。
- [ ] `python tools/godot.py check` 通过。
- [ ] 实际运行/截图验证过（涉及画面）。
- [ ] 存档/读档 roundtrip（涉及状态）。
- [ ] 文档/ADR 更新。
- [ ] 没有提交生成文件/密钥/无关改动。

---

## 10. 常见“假完成”

| 说法 | 问题 | 正确做法 |
|---|---|---|
| “代码写好了，应该能跑” | 没解析/没运行 | `check` + 运行 |
| “测试通过了” | 测试只 `assert(true)` | 断言具体行为 |
| “画面没问题” | 没截图/没看 | 截图 + 检查清单 |
| “性能应该可以” | 没测 | Profiler/FPS |
| “存档能读” | 没 roundtrip | 存→退→读→对比 |
| “MCP 返回 ok” | 没看 `game_status`/日志 | 读日志/截图 |
| “只是小改动” | 没跑回归 | 仍然 `check` |

---

## 11. 相关技能

- `godot-gdscript-headless-testing` — SceneTree runner/退出码
- `godot-gdscript` — 语法/类型
- `godot-nodes-scenes` — 场景/实例化
- `godot-export` — 导出/模板
- `performance-optimization` — 性能排查
