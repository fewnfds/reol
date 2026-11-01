# Reol

一个 **Godot 4.7.2** 的 2D 正交俯视修仙开放世界沙盒 / 宗门模拟 / RPG 项目。

> 当前阶段：M0 基座与工具链已完成；方向 v0.2 已定稿（2D 正交俯视 + 正方形格 + 高度层、单机模拟、可暂停即时战斗）；M1 已开工。
> 游戏名 `reol` 暂为占位名。

## 先读什么

| 文件 | 作用 |
|---|---|
| `AGENTS.md` | AI 每个会话必读的开发手册（规则、架构、技能路由） |
| `docs/GAME-BRIEF.md` | 游戏愿景、设计支柱、首个可玩版本的范围 |
| `docs/ARCHITECTURE.md` | 目标技术架构（tick、区块、存档、AI、UI） |
| `docs/ROADMAP.md` | 里程碑与第一冲刺任务 |
| `docs/TOOLCHAIN.md` | Godot、MCP、测试工具的安装与排错 |
| `docs/AI-WORKFLOW.md` | 如何与 AI 协作、任务拆解、验收 |
| `docs/REFERENCES.md` | 工具、示例项目、插件、素材、学习资料 |

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

5. 在 Godot 中确认 **Godot AI** 插件已启用（`addons/godot_ai` 已随仓库提供），
   在 dock 里点 **Configure** 配置 OpenCode。

## 验证

```bash
python tools/godot.py import   # 首次导入资源
python tools/godot.py test     # 无头测试
python tools/godot.py check    # 导入 + 测试
python tools/godot.py run      # 运行游戏
```

## 目录

```
addons/    第三方插件（Godot AI 等）
assets/    美术、音频、字体
data/      游戏数据（Resource / JSON）
docs/      设计、架构、工具链、参考
design/    系统设计文档与模板
scenes/    场景
scripts/   脚本
tests/     无头测试
tools/     开发脚本与 MCP 包装
```

## 技能库

项目内已内置 30+ 个 Godot / 游戏开发技能，位于 `.opencode/skills/`。
AI 会按任务自动加载；也可以手动 `@skill-id`。技能来源与许可证见
`THIRD_PARTY_NOTICES.md`。

## 许可证

项目代码尚未选择许可证。第三方技能、插件、示例项目的许可证见
`THIRD_PARTY_NOTICES.md` 与 `docs/REFERENCES.md`。
