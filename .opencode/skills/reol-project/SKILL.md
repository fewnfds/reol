---
name: reol-project
description: Reol 项目的入口技能。加载游戏愿景、当前阶段、目录/规则、文档阅读顺序和技能路由；任何 Reol 相关任务开始时先用它。
---

# Reol 项目入口

## 这个项目是什么

Reol 是一个 **Godot 4.7.2 / GDScript / 2D 等距俯视**的
**修仙开放世界沙盒 + 宗门模拟 + RPG**。

参考坐标：
- **RimWorld**：Pawn 需求/工作/心情、事件导演、可读 AI、低美术高系统
- **Dwarf Fortress**：世界生成、系统交互、失败叙事
- **Amazing Cultivation Simulator**：修仙 + 门派经营
- **Kenshi**：开放沙盒、派系、基地 + 冒险
- **Warcraft III**：等距视角、单位可读性、英雄技能、飞行高度表现
- **传统 RPG**：成长、装备、任务、对话、地牢

当前阶段：**M0 已完成，方向 v0.2 已定稿，M1 尚未开始**。只有空场景和工具链，没有玩法代码。
目标：先做 **45–60 分钟可玩的 vertical slice（“一山一宗”）**，不是一次性做完所有系统。
已定：2D 等距 + 高度层、固定角相机、单机模拟、可暂停即时战斗、脚本 AI 优先（ADR-0013～0019）。

## 每次开始前

1. 读 `AGENTS.md`（硬规则）。
2. 读 `docs/BASELINE.md` 的「已完成 / 未完成」。
3. 读 `docs/GAME-BRIEF.md` 的「当前里程碑」和「已拍板」。
4. 读 `docs/DIRECTION-V0.2.md` 的「最终结论」。
5. 读 `docs/DECISIONS.md` 最近 3 条。
6. 运行 `python tools/godot.py doctor`。
7. 用 3–6 行说明：要改什么、为什么、验收标准。

## 文档地图

| 需要什么 | 读什么 |
|---|---|
| 基座现在有什么/验证到哪 | `docs/BASELINE.md` |
| 游戏是什么/不做什么 | `docs/GAME-BRIEF.md` |
| 为什么选这个方向 | `docs/DIRECTION-V0.2.md` |
| 现在做到哪/下一步 | `docs/ROADMAP.md` |
| 代码怎么组织 | `docs/ARCHITECTURE.md` |
| 为什么这样定 | `docs/DECISIONS.md` |
| Godot 怎么用（Unity 背景） | `docs/GODOT-FOR-UNITY-DEVS.md` |
| 工具/MCP/排错 | `docs/TOOLCHAIN.md` |
| 怎么和 AI 协作 | `docs/AI-WORKFLOW.md` |
| 示例/插件/素材 | `docs/REFERENCES.md` |
| 某个系统怎么运作 | `design/systems/*.md` |

## 技能路由

按任务加载 1–3 个，不要全加载：

| 任务 | 技能 |
|---|---|
| 写 GDScript | `godot-gdscript` |
| 场景/节点/实例化/autoload | `godot-nodes-scenes` |
| 架构/tick/存档/性能 | `godot-sim-architecture` |
| 宗门 NPC/需求/工作/库存/建造 | `colony-sim-systems` |
| 大地图/区块/生成/POI | `open-world-2d` + `godot-tilemap` + `procedural-gen` |
| NPC AI/行为树/效用 | `game-ai` + `ai-behavior-trees-utility-ai` |
| RPG/任务/对话/成长 | `rpg` + `dialogue-systems` + `save-systems` |
| UI/HUD | `godot-ui-control` + `game-ui-ux` |
| 动画/手感/特效 | `godot-animation` + `game-feel` |
| 美术资产 | `create-game-assets` |
| 验证/排错 | `godot-verify` |
| 需求拆解/设计文档 | `spec-driven-game-dev` |

## 项目铁律（摘要）

- Godot **4.7.2** + **GDScript**；不引入 C#。
- 单人优先；不做联机。
- 数据驱动；不硬编码数值/ID。
- 固定 tick 做模拟；`_process` 只做渲染。
- 不手改 `addons/`；尽量不手改 `.tscn`/`.tres`。
- 不声称“完成/测试过”而没有命令输出/截图/日志。
- 一次一个系统；先写设计/验收，再实现。
- 新依赖必须说明版本/许可证/替代方案。

## 现在最该做的事

1. 运行 `python tools/godot.py doctor` 和 `check`，确认基座仍通过。
2. 读 `docs/ROADMAP.md` 的 M1，按顺序开工。
3. 第一冲刺：`main.tscn` + 2:1 等距占位 TileSet + `IsoGrid`。
4. 然后：固定角相机 → 玩家移动 → 512×512 区块 → 高度 → 迷雾 → 时间。
5. 每步都留测试/截图证据；M1 验收后再进 M2。

## 不要做的事

- 不要一上来做 50 个系统/20 个 autoload。
- 不要做真 3D/自由旋转/体素；方向已定 2D 等距（ADR-0013）。
- 不要接 LLM 做核心 AI。
- 不要做无限世界/联机/模组。
- 不要为了“以后可能”做过度抽象。
- 不要在没有可玩循环时堆内容/美术/剧情。

## 需要用户拍板时

只问 **最多 3 个** 真正阻塞的问题，并给推荐默认值。
**已拍板的方向不再重问**：2D 等距、单机、可暂停战斗、杂役起步、512×512、脚本 AI 优先。
其余按 `docs/GAME-BRIEF.md` 的默认值推进，记录到 `docs/DECISIONS.md`。
