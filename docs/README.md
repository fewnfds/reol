# Reol 文档索引

> 文档不是装饰；它们是 AI 的长期记忆。
> 先读 `AGENTS.md`，再按任务读下面。

---

## 阅读顺序

### 新会话 / 新成员
1. `../AGENTS.md` — 硬规则、目录、完成定义
2. `BASELINE.md` — 基座已完成/未完成、验证记录
3. `GAME-BRIEF.md` — 游戏是什么、不做什么、已拍板方向
4. `DIRECTION-V0.2.md` — 方向 v0.2 的完整分析与最终选择
5. `ROADMAP.md` — 现在做到哪、下一步
6. `AI-WORKFLOW.md` — 怎么和 AI 协作

### 写代码前
7. `ARCHITECTURE.md` — 目标架构、tick、存档、性能
8. `GODOT-FOR-UNITY-DEVS.md` — Godot 心智模型/API 对照
9. `DECISIONS.md` — 已定方案，别推翻

### 工具/排错
10. `TOOLCHAIN.md` — Godot、MCP、测试、故障排查
11. `REFERENCES.md` — 示例项目、插件、素材、许可证

### 设计
12. `../design/` — 系统设计、数值、边界
13. `../design/systems/_TEMPLATE.md` — 新系统文档模板

---

## 文档职责

| 文档 | 回答的问题 | 更新时机 |
|---|---|---|
| `AGENTS.md` | AI 必须遵守什么？ | 规则/目录/命令变化 |
| `BASELINE.md` | 基座现在有什么/验证到哪？ | 每次里程碑 |
| `GAME-BRIEF.md` | 做什么游戏？范围？ | 方向/范围变化 |
| `DIRECTION-V0.2.md` | 为什么选这个方向？ | 方向定稿/重大修订 |
| `ROADMAP.md` | 先做什么？怎么验收？ | 每周/里程碑 |
| `ARCHITECTURE.md` | 代码怎么组织？ | 架构决策 |
| `DECISIONS.md` | 为什么这样定？ | 每个重要决策 |
| `TOOLCHAIN.md` | 工具怎么装/怎么排错？ | 工具链变化 |
| `AI-WORKFLOW.md` | 怎么和 AI 配合？ | 流程改进 |
| `REFERENCES.md` | 去哪找资料/素材？ | 发现新资源 |
| `design/*` | 某个系统具体怎么运作？ | 系统设计/实现 |

---

## 写作规则

- **一个文档一个主题**；不要把 GDD、架构、任务混在一起。
- **先写“为什么”，再写“怎么做”**。
- 数值写单位/范围/默认值；不要写“适当”“合理”。
- 决策写日期和状态；不要悄悄改历史。
- 链接用相对路径，方便仓库迁移。
- 大段代码放技能/示例，不往文档里堆。

---

## 当前状态

- [x] AGENTS.md
- [x] BASELINE.md（M0 状态）
- [x] GAME-BRIEF.md（方向 v0.2 已定稿）
- [x] DIRECTION-V0.2.md（已定稿）
- [x] ROADMAP.md（v0.2）
- [x] ARCHITECTURE.md（v0.2）
- [x] DECISIONS.md（19 条）
- [x] TOOLCHAIN.md
- [x] AI-WORKFLOW.md
- [x] REFERENCES.md
- [ ] 系统设计文档（等第一个系统开工）
- [ ] 美术风格指南（M1/M5 前）
- [ ] 音频风格指南（M5 前）
