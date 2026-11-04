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
- 上游归属原文：`docs/third-party/awesome-gamedev-agent-skills-NOTICE`（与上述固定commit对应，2026-11-04补齐；未升级技能）
- 分发形式：选取以下技能的 `SKILL.md` 及附带资源放在 `.agents/skills/`（2026-11-02 从 `.opencode/skills/` 迁移；上游版本不变）。

### 已选取

**Godot（13）**
`godot-gdscript`、`godot-nodes-scenes`、`godot-signals-groups`、`godot-2d-movement`、
`godot-tilemap`、`godot-physics`、`godot-ui-control`、`godot-animation`、`godot-shaders`、
`godot-resources`、`godot-audio`、`godot-export`、`godot-gdscript-headless-testing`

**通用（15）**
`create-game-assets`、`game-ai`、`ai-behavior-trees-utility-ai`、`procedural-gen`、
`dialogue-systems`、`save-systems`、`audio-design`、`shader-programming`、`physics-tuning`、
`level-design`、`input-systems`、`game-feel`、`game-ui-ux`、`camera-systems`、
`performance-optimization`

**类型（3）**
`rpg`、`survival-crafting`、`roguelike`

### 未选取

Unity/Unreal/其他引擎、C#/多人、平台跳跃、卡牌、视觉小说、塔防、FPS、解谜、发布流程等。
需要时再从上游复制，不要一次全装。

### 更新

1. 固定拟采用的上游commit，保留当前版本。
2. 比较旧pin、本地修订与新pin，逐项检查选中技能及附带资源。
3. 按需合并 `.agents/skills/` 对应目录，保留本地项目修订、LICENSE和适用NOTICE；不整库覆盖。
4. 更新本文件的 commit。
5. 验证技能发现/路由、相对引用和文档结构；只有工具/游戏行为也变更时，执行相应产品验证。当前维护流程见[基础设施维护](docs/TOOLING-MAINTENANCE.md)。

---

## 3. Godot AI（编辑器插件）

- 上游：https://github.com/hi-godot/godot-ai
- 版本：**v4.3.1**
- 许可证：**MIT**
- 许可证原文：`docs/third-party/godot-ai-LICENSE`
- 分发形式：`addons/godot_ai/`（随仓库提供）
- 用途：编辑器内 MCP 工具（场景树、脚本、运行、日志、截图、输入模拟等）
- 注意：插件运行在编辑器权限下；更新走 dock 的签名校验，不要手动覆盖。

---

## 4. Coding-Solo godot-mcp（MCP 服务器）

- 上游：https://github.com/Coding-Solo/godot-mcp
- npm：`@coding-solo/godot-mcp@0.1.1`
- 许可证：**MIT**
- 分发形式：**不随仓库分发**；运行时由 `npx` 安装。
- 用途：无头启动、运行项目、抓调试输出、建场景。
- 配置：Codex 用 `tools/setup_codex.py` 生成 `.codex/config.toml` → `mcp_servers.godot` → `tools/mcp/godot_mcp.py`；旧 `opencode.json` 为 OpenCode 保留。

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

当前仓库**没有**引入第三方美术/音频素材（只有 Godot 默认 `icon.svg`）。
引入素材时：

1. 放到 `assets/third_party/<pack>/`。
2. 附 `LICENSE` 和 `SOURCE.md`（作者/链接/日期/修改）。
3. 更新本文件。
4. 检查是否允许商用/再分发。

---

## 8. 项目自身许可证

尚未选择。在发布/开源前决定（MIT / Apache-2.0 / 商业专有等）。
