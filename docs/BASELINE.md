# 基座状态（M0）

> 日期：2026-11-01
> 目的：记录“现在已经有什么、验证到什么程度、下一步讨论什么”。
> 这不是完成品；是可安全开始开发的基座。

---

## 1. 已完成

### 引擎与运行
- Godot **4.7.2 stable** 已安装并验证：
  `D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe`
- 用户环境变量 `GODOT_BIN` 已设置（新终端生效）。
- 项目主场景：`res://scenes/boot.tscn`（占位 boot）。
- 窗口基准：1280×720；2D 物理层命名已建立。

### 验证
| 检查 | 结果 |
|---|---|
| `python tools/godot.py doctor` | Godot 4.7.2，全部关键文件存在 |
| `python tools/godot.py check` | **6 passed / 0 failed**，`CHECK PASSED` |
| `python tools/godot.py run --headless --quit-after 30` | `Reol boot OK - Godot 4.7.2-stable` |
| `gdlint scripts tests` | 无问题 |
| `gdformat --check scripts tests` | 无需重排 |
| `godot` MCP `get_godot_version` | `4.7.2.stable.official.ed1daf0bf` |
| `godot` MCP `get_project_info` | `name: reol`，路径正确 |
| `godot` MCP `run_project` / `stop_project` | 可启动/停止 |

### AI 工具链
- **OpenCode** 项目配置：`opencode.json` → `mcp.godot`（Coding-Solo godot-mcp 0.1.1）。
- `godot` MCP 已连接，14 个工具可用。
- **Godot AI 4.3.1** 编辑器插件已安装到 `addons/godot_ai/`，并在 `project.godot` 中启用。
  - headless 导入日志确认插件被识别（`MCP | plugin disabled in headless mode`）。
  - **待手动**：在 GUI 编辑器里打开 Godot AI dock，点 Configure 写入 `godot-ai` 条目。
- `context7` 文档 MCP 可用。
- 无头测试脚本：`tests/run_tests.gd` + `tools/godot.py`。

### 资料库
- `AGENTS.md`：AI 每会话硬规则、目录、DoD、技能路由。
- 37 个技能（`.opencode/skills/`）：
  - 31 个来自 `awesome-gamedev-agent-skills`（Apache-2.0，固定 commit）。
  - 6 个项目专属：`reol-project`、`godot-sim-architecture`、`colony-sim-systems`、
    `open-world-2d`、`godot-verify`、`spec-driven-game-dev`。
- 文档：
  - `docs/GAME-BRIEF.md`（愿景/范围/开放问题）
  - `docs/ARCHITECTURE.md`（tick/实体/数据/区块/存档/性能）
  - `docs/ROADMAP.md`（M0–M5 + 第一冲刺）
  - `docs/GODOT-FOR-UNITY-DEVS.md`
  - `docs/TOOLCHAIN.md`（安装/MCP/排错）
  - `docs/AI-WORKFLOW.md`
  - `docs/REFERENCES.md`（示例项目/插件/素材/许可证）
  - `docs/DECISIONS.md`（12 条 ADR）
- `design/` 系统设计模板；`data/`、`assets/` 约定。
- `THIRD_PARTY_NOTICES.md` + 许可证原文。
- Git 仓库已初始化，根提交 `40f307c`。
- GitHub Actions CI 模板（Godot 4.7.2 下载 + `check`）。

---

## 2. 尚未完成 / 需要你参与

| 事项 | 为什么还没做 |
|---|---|
| Godot AI dock Configure | 需要 GUI 编辑器交互；它会写全局/项目 MCP 配置 |
| Boot 场景截图 | 需要真实窗口渲染；headless 无画面 |
| 导出模板 | 打包时才需要；Editor → Manage Export Templates |
| 设计开放问题 1/2/3 | 需要你拍板，见 `docs/GAME-BRIEF.md` |
| 项目许可证 | 你还没选（MIT / Apache-2.0 / 专有） |
| CI 首次运行 | 需要 GitHub remote |
| GUT | 暂用自带 headless runner；复杂后替换 |

---

## 3. 下一个会话怎么开始

```text
读 AGENTS.md 和 docs/BASELINE.md。
当前 M0 已完成；先不要写玩法。
我们讨论 docs/GAME-BRIEF.md 的开放问题 1/2/3，确定后更新 DECISIONS.md。
```

然后从 `docs/ROADMAP.md` 的 M1 第一个任务开始：玩家移动 + 相机 + 地图 + 时间。

---

## 4. 建议讨论的三个问题

1. **视角/美术**：2D 32×32 像素风（默认），还是 16×16 / 手绘 HD / 2.5D？
2. **玩家角色**：单角色可操控 + 可指挥殖民者（默认），还是纯上帝视角 / 纯单角色 ARPG？
3. **战斗**：实时 + 空格暂停/慢放（默认），还是回合制 / 纯即时？

这三个会决定相机、输入、AI、UI、战斗和美术管线。确认后 M1 才能稳定推进。

---

## 5. 已知风险

- 范围过大：开放世界 + 殖民 + RPG + 建造，任何一个都能吞掉数月。
- 模拟性能：Pawn 数量/工作评估/寻路是主要热点。
- 存档腐烂：字段会频繁变；必须从第一天做版本化。
- AI 幻觉 API：所有 Godot 4.7 API 都要用文档/context7/最小示例验证。
- 第三方插件：Godot AI 有编辑器权限；pin 版本，走官方更新。
