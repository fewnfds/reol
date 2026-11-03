# Reol

一个 **Godot 4.7.2** 的 2D 正交俯视修仙开放世界沙盒 / 宗门模拟 / RPG 项目。

> 当前：M2 活社会切片；双聚落连续性与跨聚落办事、互助基础闭环已验证。
> reol = reroll。当前构建与验证只以 [BASELINE](docs/BASELINE.md) 为准。

文件、计划、资源如何划分，见 [PROJECT-STRUCTURE](docs/PROJECT-STRUCTURE.md)。全部文档入口见 [docs/README](docs/README.md)。
最新重构、实际已实现功能与限制见 [Demo代码核对](docs/DEMO-REFACTOR-REPORT.md)。
完整游戏的分期、有限1.0范围与验收见[长期方案](docs/plans/full_game_program.md)；工具实际可用性见[本机审计](docs/DEVELOPMENT-TOOLS-AUDIT.md)，资源候选与Goal接续见[搜集工作包](docs/plans/resource_tooling_scout.md)。这些是后续规划，不表示完整游戏已实现。
最新[战斗、修行与纸娃娃详细设计](docs/plans/combat_character_design.md)落实无固定职业、学习形成能力、衣着独立社交价值的方向。已接几何动作对练样本；完整战斗、修行网和纸娃娃换装仍待实现。当前W5-a有限资格/核验/一次取药链已验收，用户要求暂停Goal进行理念讨论，进度见[通报](docs/PROGRESS-20261103.md)。

## 先读什么

| 文件 | 作用 |
|---|---|
| `AGENTS.md` | AI 每个会话必读的开发手册（规则、架构、技能路由） |
| `docs/GAME-BRIEF.md` | 游戏愿景、设计支柱、首个可玩版本的范围 |
| `docs/ARCHITECTURE.md` | 当前模块、依赖方向与状态归属 |
| `docs/ROADMAP.md` | 里程碑与近期依赖顺序 |
| `docs/plans/full_game_program.md` | 完整游戏路线；先玩法、后正式视听 |
| `docs/plans/world_foundation.md` | 下一次实施的P0首包；Demo重构保留已完成状态 |
| `docs/TOOLCHAIN.md` | Godot、MCP、测试工具的安装与排错 |
| `docs/AI-WORKFLOW.md` | 如何与 AI 协作、任务拆解、验收 |
| `docs/plans/resource_tooling_scout.md` | 新核查的工具/资源入口；旧REFERENCES保留学习索引 |

## 快速开始

1. 确认 **Godot 4.7.2** 可用（本机：`D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe`）。
2. 确认环境变量 `GODOT_BIN` 指向该文件（新终端生效）。
3. 运行环境诊断：

   ```bash
   python tools/godot.py doctor
   ```

4. 打开项目：

   ```bash
   python tools/godot.py editor
   ```

5. 配置 Codex 的项目工具：`python tools/setup_codex.py`。
   在 Godot 中确认 **Godot AI** 插件已启用（`addons/godot_ai` 已随仓库提供），
   在 dock 里点 **Configure → Codex**。重新打开 Codex 项目后检查 MCP 工具。
   详细配置与迁移记录见 `docs/TOOLCHAIN.md`。

## 验证

```bash
python tools/godot.py import   # 首次导入资源
python tools/godot.py test     # 无头测试
python tools/godot.py check    # 导入 + 测试
python tools/check_structure.py # 文档入口、链接与移动路径
python -m unittest discover -s tests -p 'test_*.py' # Python工具测试
python tools/godot.py run      # 运行游戏
```

## 目录

```
addons/    第三方插件（Godot AI 等）
assets/    美术、音频、字体
data/      definitions/ 内容规则；scenarios/ 开局装配
docs/      当前状态、plans/ 工作包、架构、qa/ 证据、archive/ 历史
design/    systems/ 游戏规则；research/ 来源和取舍
scenes/    场景
scripts/   sim/ 规则；runtime/ 适配；persistence/ 文件存读
tests/     sim/ 规则测试；runtime/ 整合；Python工具测试
tools/     开发脚本与 MCP 包装
```

## 技能库

项目内已内置 37 个 Godot / 游戏开发技能，位于 `.agents/skills/`。
Codex 会按任务发现技能；也可以手动 `$skill-id`。技能来源与许可证见
`THIRD_PARTY_NOTICES.md`。

## 许可证

项目代码尚未选择许可证。第三方技能、插件、示例项目的许可证见
`THIRD_PARTY_NOTICES.md` 与 `docs/REFERENCES.md`。
