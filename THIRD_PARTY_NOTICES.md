# 第三方组件与许可证

> 本文件记录随仓库分发或直接依赖的第三方组件。
> 发布前请做一次完整审计；本文件不是法律意见。

---

## 1. Godot Engine

- 组件：Godot Engine 4.7.2
- 用途：游戏引擎
- 许可证：MIT
- 链接：https://godotengine.org/
- 说明：项目本身由 Godot 创建；引擎不随本仓库分发。

---

## 2. awesome-gamedev-agent-skills（技能库）

- 上游：https://github.com/gamedev-skills/awesome-gamedev-agent-skills
- 许可证：**Apache-2.0**
- 固定 commit：`19d93f97c9c1ea0f8b306e77aa81e0d3e352d3e9`
- 许可证原文：`docs/third-party/awesome-gamedev-agent-skills-LICENSE`
- 上游归属原文：`docs/third-party/awesome-gamedev-agent-skills-NOTICE`，对应上述固定commit。
- 当前分发：`.agents/skills/create-game-assets/`保留图片QA脚本、依赖声明和改写后的二维指导；`godot-verify/references/troubleshooting.md`含经本地收窄的headless排错；原资源引用检查器恢复到`godot-gdscript/scripts/check_godot_project.py`，其代码未修改。
- 本地修订：2026-11-18复核前轮删减，原Godot/游戏领域指导按Reol纯二维GDScript、Packed模拟与已有owner重新编写/合并。含派生指导的入口为`godot-gdscript`、`godot-resources`、`godot-ui-input`、`godot-motion-navigation`、`godot-decision-systems`、`colony-sim-systems`、`godot-character-rules`、`dialogue-systems`、`save-systems`、`godot-world-generation`、`godot-2d-presentation`、`godot-audio`、`godot-export`、`performance-optimization`与`level-design`，各文件含本地重写/合并说明及本页链接。未恢复三维、跨引擎实现和品类玩法模板。
- 原选取的31个第三方入口不再整套分发；`godot-sim-architecture`及`godot-verify/SKILL.md`为项目自有指导。图片QA脚本、依赖声明及恢复的引用检查器保持原代码；其新增隔离反例检查为本项目代码。Apache许可证及NOTICE原文继续保留，本地差异由Git维护，不因重命名/合并丢失来源。
- 本次比较的其他skill库与官方资料仅阅读/链接，未复制其代码、安装或形成新运行依赖；不以本次检索HEAD更改上述采用pin。

### 更新

维护方法见[工具配置与维护](docs/engineering/tooling/setup.md)；本页只登记采用版本、许可和本地修订。

---

## 3. Godot AI（编辑器插件）

- 上游：https://github.com/hi-godot/godot-ai
- 版本：**v4.4.1**；源commit `643c64f3edf984a9668b3043f4d20ebb2bbec6b6`
- 许可证：**MIT**
- 许可证原文：`docs/third-party/godot-ai-LICENSE`
- 分发形式：`addons/godot_ai/`（随仓库提供）
- 用途：编辑器内 MCP 工具（场景树、脚本、运行、日志、截图、输入模拟等）
- 本地修订：插件源文件未作修改。
- 配置与更新方法：[工具配置与维护](docs/engineering/tooling/setup.md)。

---

## 4. Coding-Solo godot-mcp（MCP 服务器）

- 上游：https://github.com/Coding-Solo/godot-mcp
- npm：`@coding-solo/godot-mcp@0.1.1`
- 许可证：**MIT**
- 分发形式：**不随仓库分发**；运行时由 `npx` 安装。
- 用途：无头启动、运行项目、抓调试输出、建场景。
- 配置：Coding-Solo 的可选本机连接独立于游戏运行，配置由使用者在本机维护。

---

## 5. context7（文档 MCP）

- 服务：https://mcp.context7.com/mcp
- 用途：查询 Godot / 第三方库文档
- 分发形式：远程 MCP，不随仓库分发。
- 注意：不要把私有代码/密钥发到第三方服务。

---

## 6. 仅作为参考、未复制代码的项目

以下项目只用于阅读/学习，**没有复制代码或素材**到本仓库：

| 项目 | 许可证 | 注意 |
|---|---|---|
| Neon Harbor | PolyForm Noncommercial 1.0.0 + CC BY-NC 4.0 | **非商业**；不要复制代码/内容到商业项目 |
| GDQuest Open RPG | MIT | 可学习/复用；保留声明 |
| Colony Sim Tutorial | MIT | 可学习/复用；保留声明 |
| Microverse | MIT | 素材（LimeZu）另有许可 |
| Harvester / godot-2d-space-game | MIT | 可学习/复用 |
| Godot Demo Projects | MIT | 各 demo 素材可能不同 |
| Claude-Code-Game-Studios | MIT | 只借流程/模板，未复制 |
| LimboAI / Beehave / Dialogue Manager / Phantom Camera / GUT / gdtoolkit | MIT | 未安装；安装时另行记录 |

---

## 7. 素材

已采用Kenney Tiny Town、Tiny Farm、Tiny Dungeon的CC0切片。生成素材、程序绘制素材及第三方资源的完整清单和权利边界见[素材来源](assets/README.md#来源与权利记录)，各包保留原始许可与SOURCE记录。

---

## 8. 项目自身许可证

尚未选择。在发布/开源前决定（MIT / Apache-2.0 / 商业专有等）。

---

## 9. pbzona/godot-skills（设计指导）

- 上游：https://github.com/pbzona/godot-skills
- 固定commit：`0ad8f3c58d54580a57a1a6de3cd345a1d9376e3d`
- 许可证：**MIT**；原文与版权声明见`docs/third-party/pbzona-godot-skills-LICENSE`。
- 来源：`skills/game-systems-design/SKILL.md`、`skills/game-balance/SKILL.md`。
- 当前分发：`.agents/skills/simulation-game-design/SKILL.md`；2026-11-18按Reol玩家单角色、自治社会、纯二维、原owner与按需验证重写/收窄。采用体验/规则/反馈的联系、存量流量、机会条件与证据分层；移除上游多份必交文档、全套平衡/遥测流程和泛引擎入口。
- 只采用开发指导，不安装整库、运行依赖或第三方模拟后端；此技能的许可不改变项目游戏代码的许可证状态。
