# Reol — 参考资料库

> 截至 2026-11-01。链接会过期；以官方页面为准。
> 每条都标注“借什么”，避免无脑收藏。

---

## 1. 官方 Godot

| 资源 | 链接 | 用途 |
|---|---|---|
| Godot 4.7 文档 | https://docs.godotengine.org/en/4.7/ | **API 的第一来源** |
| 中文文档 | https://docs.godotengine.org/zh-cn/4.7/ | 中文对照 |
| GDScript 风格指南 | https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html | 命名/格式 |
| 最佳实践 | https://docs.godotengine.org/en/4.7/tutorials/best_practices/index.html | 架构/性能 |
| 2D 入门 | https://docs.godotengine.org/en/4.7/getting_started/step_by_step/index.html | 先跑一遍 |
| 官方 Demo 项目 | https://github.com/godotengine/godot-demo-projects | 2D/3D/导航/UI 示例 |
| Asset Library | https://godotengine.org/asset-library/asset | 插件/素材 |
| 下载 | https://godotengine.org/download/windows/ | 4.7.2 标准版 |
| 中文官网 | https://godotengine.org/zh-cn/ | 新闻/下载 |

**用法：** 不确定 API 时，先查 4.7 文档，再用 context7 查第三方库；不要凭记忆写。

---

## 2. AI 开发工具

### 2.1 MCP / 编辑器连接

| 项目 | 链接 | 星 | 许可证 | 借什么 |
|---|---|---:|---|---|
| **Godot AI** | https://github.com/hi-godot/godot-ai | 3.3k | MIT | **本项目首选**：实时编辑器、场景树、脚本校验、运行/日志/截图、输入模拟 |
| **Coding-Solo godot-mcp** | https://github.com/Coding-Solo/godot-mcp | 6.4k | MIT | 轻量启动/运行/抓调试输出；本项目备用 |
| Godot-MCP-Native | https://github.com/yurineko73/Godot-MCP-Native | 865 | MIT | 原生插件、无依赖、中文；轻量替代 |
| godot-mcp-pro | https://github.com/youichi-uda/godot-mcp-pro | 641 | 付费 $15 | 162 工具；功能多，先不需要 |
| ee0pdt/Godot-MCP | https://github.com/ee0pdt/Godot-MCP | 621 | MIT | 编辑器插件、场景编辑；备选 |
| DaxianLee/godot-mcp | https://github.com/DaxianLee/godot-mcp | 550 | MIT | 原生插件、一键配置；备选 |
| tugcantopaloglu/godot-mcp | https://github.com/tugcantopaloglu/godot-mcp | 507 | MIT | 157 工具，宣称 4.7；备选 |
| IvanMurzak/Godot-MCP | https://github.com/IvanMurzak/Godot-MCP | 319 | Apache-2.0 | C#/云端；本项目不用 C# |

**选择原则：** 一个主 MCP（Godot AI）+ 一个无头备用（Coding-Solo）足够。
工具越多，上下文/权限/冲突成本越高。

### 2.2 技能库 / 工作流

| 项目 | 链接 | 星 | 许可证 | 借什么 |
|---|---|---:|---|---|
| **awesome-gamedev-agent-skills** | https://github.com/gamedev-skills/awesome-gamedev-agent-skills | 6.4k | Apache-2.0 | **本项目技能库来源**：Godot 4.7 + 通用游戏开发 77 技能 |
| **Claude-Code-Game-Studios** | https://github.com/Donchitos/Claude-Code-Game-Studios | 31.5k | MIT | 工作室式流程、GDD 模板、Godot specialist 规则；**借流程，不照搬 49 agents** |
| Agent Skills 标准 | https://agentskills.io | — | — | `SKILL.md` 格式/兼容性 |

**Claude-Code-Game-Studios 怎么用：**
- 它的 74 个 skill 是 Claude Code 的 slash commands，不是纯知识库；直接全搬会太重。
- 值得借：`godot-specialist` 的引擎规则、`design/gdd` 模板、`/create-stories` `/dev-story` 的拆分思路。
- 不值得借：49 个 agent 的层级、强制的 30 份文档、hooks 全家桶。

### 2.3 LLM NPC / 社交模拟

| 项目 | 链接 | 星 | 许可证 | 借什么 |
|---|---|---:|---|---|
| **Microverse** | https://github.com/KsanaDock/Microverse | 2.5k | MIT | Godot 4 + LLM NPC 记忆/对话/任务；**只借技术，不做核心依赖** |
| NobodyWho | https://github.com/nobodywho-ooo/nobodywho | 1.7k | MIT | 本地 LLM 推理；后期可选 |

> 不要一上来接 LLM。先把规则驱动的 NPC 做好；LLM 只做“对话风味”，不要做核心模拟。

---

## 3. 示例项目（按相关度排序）

### 3.1 Neon Harbor — 最接近的参考

- 链接：https://github.com/quzkhanh/neon-harbor
- 引擎：**Godot 4.7.2**，GDScript，Compatibility
- 类型：2D 俯视开放世界动作（238×186 tile 城市、9 区、日夜、通缉、任务、车辆）
- 许可证：**PolyForm Noncommercial 1.0.0**（代码）+ CC BY-NC 4.0（内容）
- **借什么：**
  - 大地图从 ASCII 加载到 `TileMapLayer` 的管线。
  - 数据驱动武器/车辆（JSON）。
  - 存档 `user://save.json` 的结构。
  - `tools/checks/` 的无头测试/截图/地图校验思路。
  - 项目分层：`data/`、`scripts/autoload/`、`actors/`、`world/`、`tests/`。
- **不要：** 复制代码到商业项目；它的许可证是非商业。

### 3.2 GDQuest Open RPG

- 链接：https://github.com/gdquest-demos/godot-open-rpg
- 引擎：**Godot 4.7.2**，GDScript
- 类型：传统回合制 RPG（战斗、背包、成长、地图切换、对话）
- 许可证：MIT
- **借什么：** 回合制战斗结构、UI/菜单组织、角色数据、地图切换。
- **不要：** 它的回合制假设不适合实时殖民 sim；只借模块。

### 3.3 Colony Sim Tutorial

- 链接：https://github.com/davisbrandon02/colony-sim-tutorial
- 视频：https://www.youtube.com/playlist?list=PLM-hFhoXjVl1hq0j9lxgRCzxkBpDZhDlT
- 引擎：Godot 4，GDScript
- 类型：殖民 sim 教学（TileMap、寻路、基础 AI）
- 许可证：MIT
- **借什么：** 最小殖民循环、TileMap/寻路入门。
- **不要：** 它的完成度不高（README 自己列了 TODO）；只当入门。

### 3.4 Microverse

- 链接：https://github.com/KsanaDock/Microverse
- 引擎：Godot 4.3+，GDScript
- 类型：LLM 多智能体社交沙盒（8 个 AI 角色、记忆、任务、对话）
- 许可证：MIT（素材另有许可，LimeZu）
- **借什么：** LLM API 封装、记忆存储、对话 UI、角色管理器。
- **不要：** 把 LLM 当核心玩法；不要把 API key 写进仓库。

### 3.5 Harvester / Godot 2D Space Game

- 链接：https://github.com/GDQuest/godot-game-harvester
- 旧仓库：https://github.com/gdquest-demos/godot-2d-space-game
- 引擎：Godot 4，GDScript
- 类型：俯视太空采集/升级/海盗
- 许可证：MIT
- **借什么：** 程序生成地图、Steering AI、升级/经济循环、GDQuest 代码风格。

### 3.6 Godot Demo Projects

- 链接：https://github.com/godotengine/godot-demo-projects
- 许可证：MIT（各 demo 素材可能不同）
- **借什么：** 官方 API 用法：2D 移动、TileMap、Navigation、Animation、UI、Multiplayer（后期）。

### 3.7 设计参考（非开源代码）

- **RimWorld**：Pawn 需求/工作/心情、事件导演、可读 AI、低美术高系统。
- **Dwarf Fortress**：世界生成、历史、系统交互、失败叙事。
- **Amazing Cultivation Simulator（了不起的修仙模拟器）**：修仙 + 门派经营 + RimWorld 式系统；借“宗门日常/风水/炼丹/事件”，不借过多并行系统和复杂 UI。
- **Tale of Immortal（鬼谷八荒）**：开放世界修仙、突破、随机事件、人际关系；借成长/事件节奏，不借重复刷。
- **The Scroll of Taiwu（太吾绘卷）**：世界/势力/关系网、传承、系统叙事；借关系网，不借过度复杂的信息结构。
- **Path of Immortality（觅长生）**：时间压力、事件、炼丹/修炼循环；借时间感，不借线性流程。
- **Kenshi**：开放沙盒、派系、基地+冒险；借“无主角光环”，不借粗糙手感。
- **Warcraft III**：等距视角、单位可读性、英雄技能、飞行高度表现；借可读性，不借 RTS 多线微操。
- **World of Warcraft**：阵营/声望/敌友、任务、世界感；借声望结构，不借真 MMO 规模。
- **Necesse / Core Keeper**：俯视建造/探索/战斗的轻量循环。
- **Stardew Valley**：日常节奏、亲切感、UI。

> 本项目已选 **2D 正交俯视（正方形格）**；等距/3D 参考只作为未来备选，不进入 v0.1。

---

## 4. 插件（按需，不要全装）

| 需求 | 插件 | 链接 | 许可证 | 备注 |
|---|---|---|---|---|
| 行为树/状态机 | **LimboAI** | https://github.com/limbonaut/limboai | MIT | 功能全，含可视化调试 |
| 行为树 | Beehave | https://github.com/bitbrain/beehave | MIT | 更轻 |
| 对话 | Dialogue Manager | https://github.com/nathanhoad/godot_dialogue_manager | MIT | 成熟，适合 RPG |
| 相机 | Phantom Camera | https://github.com/ramokz/phantom-camera | MIT | 2D/3D 跟随/震屏/限制 |
| 测试 | GUT | https://github.com/bitwes/Gut | MIT | 复杂后替换自带 runner |
| Lint/格式化 | gdtoolkit | https://github.com/Scony/godot-gdscript-toolkit | MIT | `gdlint` / `gdformat` |
| 转向/群体 | Godot Steering AI | https://github.com/GDQuest/godot-steering-ai-framework | MIT | 动物/人群 |

安装前检查：
- 支持 Godot 4.7？
- 最近 6 个月有提交？
- 许可证允许商用？
- 能否干净移除？
- 是否需要额外服务/端口/权限？

---

## 5. 美术 / 音频素材

| 来源 | 链接 | 许可证 | 适合 |
|---|---|---|---|
| **Kenney** | https://kenney.nl/assets | CC0 | 2D/3D 占位、UI、音效；首选 |
| **Kenney Isometric** | https://kenney.nl/assets?q=isometric | CC0 | 2D 等距 tile（备选，不采用） |
| **Kenney Top-down** | https://kenney.nl/assets?q=top-down | CC0 | 2D 俯视 tile/角色占位 |
| **LimeZu** | https://limezu.itch.io/ | 各包不同（多为付费） | 精致 2D 室内/角色；Microverse 用过 |
| **Quaternius** | https://quaternius.com/ | CC0 | 3D 低模（本项目不做 3D，留作未来） |
| **KayKit** | https://kaylousberg.itch.io/ | CC0/付费 | 3D 角色/场景 |
| **OpenGameArt** | https://opengameart.org/ | 混合 | 免费素材，逐项看许可 |
| **Poly Pizza** | https://poly.pizza/ | CC0/混合 | 3D 低模 |
| **Freesound** | https://freesound.org/ | 混合 | 音效，逐项看许可 |
| **Sonniss GDC** | https://sonniss.com/gameaudiogdc |  royalty-free | 大批音效包 |

规则：
- 每个素材包在 `assets/third_party/<pack>/LICENSE` 放许可证原文。
- 记录来源、作者、许可证、是否修改。
- 不把付费素材原样再分发。
- 先用占位；M4 再统一美术。

---

## 6. 学习资源

| 资源 | 链接 | 适合 |
|---|---|---|
| GDQuest | https://www.gdquest.com/ | 系统课程、免费教程、开源 demo |
| GDQuest YouTube | https://www.youtube.com/@GDQuest | 短教程 |
| HeartBeast | https://www.youtube.com/@HeartBeast | Godot 4 入门/ARPG |
| KidsCanCode | https://kidscancode.org/godot_recipes/4.x/ | 代码食谱、2D/3D |
| Godot Forum | https://forum.godotengine.org/ | 提问/搜索 |
| r/godot | https://www.reddit.com/r/godot/ | 社区/展示 |
| Godot Discord | https://discord.gg/godotengine | 实时求助 |
| 中文文档 | https://docs.godotengine.org/zh-cn/4.7/ | 中文 API |

**学习顺序：** 官方 2D 入门 → GDScript 风格 → TileMapLayer → Signal → Resource → 存档 → 导航 → 动画 → UI。
不要先看 50 小时全流程教程；直接做 M1。

---

## 7. 许可证速查（重要）

| 来源 | 许可证 | 能商用？ | 能改？ | 注意 |
|---|---|---|---|---|
| Godot Engine | MIT | ✅ | ✅ | 保留版权声明 |
| Godot AI | MIT | ✅ | ✅ | 第三方插件，自行评估 |
| Coding-Solo MCP | MIT | ✅ | ✅ | |
| awesome-gamedev-agent-skills | Apache-2.0 | ✅ | ✅ | 保留 NOTICE/LICENSE |
| Claude-Code-Game-Studios | MIT | ✅ | ✅ | |
| Neon Harbor | PolyForm Noncommercial + CC BY-NC | ❌ | ✅ | **不能用于商业项目** |
| Microverse | MIT | ✅ | ✅ | 素材（LimeZu）另有许可 |
| GDQuest Open RPG | MIT | ✅ | ✅ | 素材（Kenney）CC0 |
| Colony Sim Tutorial | MIT | ✅ | ✅ | |
| Kenney | CC0 | ✅ | ✅ | 无需署名（建议署名） |
| LimeZu | 各包不同 | 看包 | 看包 | 不要原样再分发 |
| OpenGameArt/Freesound | 混合 | 逐项 | 逐项 | 必须逐个看 |

> 本文件不是法律意见。发布前做一次许可证审计。

---

## 8. 如何评估一个新工具

看到“Godot AI 工具”先问：

- [ ] 支持 Godot **4.7.2** 吗？最近更新是什么时候？
- [ ] 许可证允许你的使用方式吗？
- [ ] 它改你的项目文件吗？能回滚吗？
- [ ] 它需要开端口/装服务/给编辑器权限吗？
- [ ] 工具有多少？上下文开销多大？
- [ ] 出问题能卸载干净吗？
- [ ] 有没有更简单的内置方案？

**默认：不装。** 直到它解决一个你真实遇到的痛点。
