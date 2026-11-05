# 开发工具、Skill、MCP 与 Godot 插件审计

> 历史记录：版本、测试结果、任务顺序与待办只描述当时，不是当前状态或实施队列。

> **历史证据：** 此页保留2026-11-02审计时点，不是当前配置或待办。其中两条MCP均启用、Godot AI 4.3.1等表述为当时记录；现状以[套件实装](../../engineering/tooling/setup.md)为准，官方更新来源及历史研究见[基础设施维护](../../engineering/tooling/maintenance.md)。本地Sol审查与CI规则以[审查工作流](../../engineering/workflow/code-review.md)为准。

日期：2026-11-02。范围：本机 Reol 检出、当前 Codex 会话的可见能力与少量只读调用。**本轮没有安装、升级、删除工具，没有修改项目或全局配置。** 本文不公开本机绝对路径、连接端口、令牌或环境变量值。

结论：已有的项目技能和三条游戏相关 MCP 路径足够继续玩法开发；没有发现必须重做迁移或替换工具链的证据。当前缺口主要是发布工具准备、持续性能测量和项目专属长期验证流程，不是再安装一套 AI 框架。

## 1. 配置究竟在哪里

Skill 是工作方法，MCP 是可调用工具连接，Godot addon 是引擎插件。三者可以配合，不能因名字相似视为同一项安装。

| 位置 | 本次实际发现 | 作用与保留方式 |
|---|---|---|
| 项目 `.agents/skills/` | 37 个 `SKILL.md`，连同参考/脚本共 87 个文件 | 本项目共享的游戏开发方法；随仓库管理 |
| 项目 `AGENTS.md` | 项目入口、约束和技能路由 | 当前开发规则；不能由第三方技能示例反向覆盖 |
| 项目 `.codex/config.toml` | `godot`、`context7` 两个 MCP 条目，均启用 | 本机项目连接；有本地路径，已由 `.codex/.gitignore` 排除，不应提交 |
| 用户 `~/.codex/config.toml` | `godot-ai`、`node_repl`、`langchain-docs` 条目；本项目有 `trusted` 记录 | 跨项目设置；本轮仅提取必要条目的脱敏摘要，未改模型、权限及其他配置 |
| 用户 `~/.agents/skills/` | 发现 `officeCLI`、`sap-extension-creator`；与这37个项目技能无同名重叠 | 个人通用技能；不迁入游戏仓库 |
| Codex 系统及插件技能 | 当前目录显示 `openai-docs`、`imagegen`、`skill-creator`、`skill-installer`、插件管理等 | 由宿主提供；出现技能说明不等于其所有外部服务均已连接或实测 |
| 项目 `addons/` | 仅 `godot_ai`，已在 `project.godot` 启用 | Godot 编辑器插件；不手改上游文件 |
| 旧 `opencode.json` | 文件仍在；`.opencode/skills/` 已不存在 | 为 OpenCode 保留；不作为 Codex 生效配置，不需要重复迁移 |

项目和用户配置之间**未发现同名 MCP 服务器条目重复**。`godot` 与 `godot-ai` 是两个用途不同的工具，不是重复安装同一个服务器。Codex 宿主还可通过内置插件提供工具，不能只看两份 TOML 推断全部工具来源。

官方规则：用户配置与受信任项目配置分层；技能可从仓库、用户、系统等位置发现。当前本地结构与此相符。[配置层级](https://developers.openai.com/codex/config-basic)、[MCP 配置](https://developers.openai.com/codex/mcp)、[技能发现](https://developers.openai.com/codex/skills)。

## 2. 本轮实际调用结果

“配置存在”“工具暴露”“调用成功”分别记录。一次读状态成功不保证所有写操作、导出或长时间会话都成功。

| 能力 | 配置/可见情况 | 本轮只读证据 | 尚未验证 |
|---|---|---|---|
| Godot AI | 全局 `godot-ai`；当前会话暴露47个工具 | `editor_state` 和会话列表成功；Godot 4.7.2、插件/后端均4.3.1；当前项目游戏 `live`，helper可用 | 本轮未调用改节点、改脚本、输入、运行/停止或截图操作 |
| Coding-Solo Godot MCP | 项目 `godot`；暴露14个工具 | `get_godot_version` 返回 `4.7.2.stable.official.ed1daf0bf`；本地npm缓存包元信息为0.1.1/MIT | 本轮未通过它新建场景、启动另一游戏进程或改资源 |
| Context7 | 项目 `context7`；暴露2个工具 | 库解析成功；对官方文档4.7分支的查询成功，返回可追溯的Godot来源 | 不保证每个冷门API都有资料；仍需核对版本与实际导入/运行 |
| Node REPL | 全局条目存在，工具已暴露 | 未专项调用；仅核对其配置位置 | 不能把本轮审计算作脚本执行或图像处理验证 |
| LangChain Docs | 全局条目存在，工具已暴露 | 未专项调用 | 当前GDScript玩法开发不需要；既有条目不等于要把LangChain引入游戏 |
| 网络检索/浏览能力 | 当前宿主已暴露 | 本轮查阅并打开官方Codex配置/技能文档成功 | 游戏素材下载、许可复核与导入仍是另一个任务 |
| 插件管理 | 当前宿主已暴露管理工具 | 已读使用技能；没有更改连接/权限或安装插件 | 不把“可搜索目录”当成“候选服务已连接” |

另外完成：

```text
python tools/godot.py doctor
Version: 4.7.2
project.godot / import cache / godot_ai / test runner / skills / config: present

python tools/setup_codex.py --check
Project skills: 37
PRESENT MCP: godot
PRESENT MCP: context7
Codex project config OK
```

以上是工具链审计证据，**不是一次新的全游戏功能验收**。当前玩法测试与完成度仍以[BASELINE](../../status/baseline.md)为准。历史迁移调用结果保存在[TOOLCHAIN](../../engineering/tooling/usage.md)，不能用历史结果替代本轮未做的操作。

## 3. 实际版本、来源与许可证

| 组件 | 本机/仓库证据 | 版本与许可 | 来源与边界 |
|---|---|---|---|
| Godot Engine | doctor、备用MCP、编辑器状态均一致 | 4.7.2；MIT | [官方引擎](https://godotengine.org/)。本轮未更换引擎 |
| Godot AI addon | `addons/godot_ai/plugin.cfg`、本地LICENSE、会话后端版本 | 4.3.1；MIT | [hi-godot/godot-ai](https://github.com/hi-godot/godot-ai)。上游地址亦与插件更新器常量一致；本轮未核验所有文件相对发行包的签名/哈希，未判断是否最新版本 |
| Coding-Solo MCP | `tools/mcp/godot_mcp.py` pin值、本机缓存的package.json与LICENSE | `@coding-solo/godot-mcp@0.1.1`；MIT | [Coding-Solo/godot-mcp](https://github.com/Coding-Solo/godot-mcp)。本轮只读取已有缓存，没有运行安装命令 |
| 上游游戏开发技能 | 第三方声明、仓库许可证副本、当前技能文件 | 记录的固定commit：`19d93f97c9c1ea0f8b306e77aa81e0d3e352d3e9`；Apache-2.0 | [awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)。31个选取技能；本轮不声称重新完成了逐文件上游哈希复核 |
| 项目定制技能 | `reol-project`、`godot-sim-architecture`、`godot-verify`、`colony-sim-systems`、`open-world-2d`、`spec-driven-game-dev` | 6个项目技能；依仓库规则维护 | 与31个上游选取项合计37个；项目自身发行许可证仍未选择 |
| Context7 | 项目配置服务地址、当前查询结果 | 远程服务，项目没有固定服务器版本 | [Context7](https://github.com/upstash/context7)。本轮不对远程服务许可、SLA或未来兼容性作保证；查询只使用公开技术主题 |

许可证原文与原有分发说明见[THIRD_PARTY_NOTICES](../../../THIRD_PARTY_NOTICES.md)。开发工具许可不自动覆盖从示例仓库取得的字体、音效、音乐和贴图；素材要按实际包单独核验。

环境读取还确认：Python 3.14.3、Node.js 25.2.1、npm 11.14.1、Git 2.53.0、uv 0.11.28。素材预览脚本依赖的Pillow可导入，版本12.2.0，落在现有`Pillow>=10,<14`范围内；本轮未运行该脚本完整流水线。

## 4. 现有技能是否失效或重复

- 37个技能的`name`与目录一致，`description`字段均存在。去掉代码示例后，Markdown相对文件链接检查未发现缺失；全局配置未发现禁用本项目技能的条目。这证明文件结构与入口成立，不代表所有教学代码已在项目中测试。
- 本项目的37个技能已出现在当前会话技能目录；用户通用技能与其没有同名重叠。`game-ai`/`ai-behavior-trees-utility-ai`、`game-ui-ux`/`godot-ui-control`等是通用设计与引擎落地两层，按任务选择即可，无需合并或删除。
- `godot-sim-architecture`仍有通用旧示例：128×128小地图起步，以及“预算不足宁可丢时间”的示例说明。**当前项目已经采用512×512首区和保留待处理时间的连续性契约，不能照抄这些例子。** 后续若更新技能，应把通用示例标明适用范围；本轮只记录，不改文件。
- `save-systems`与对话技能中的代码示例不是Reol存档/对话接口。把其中示例当已经安装的运行库，会制造第二套执行器或存档体系。以当前sim/runtime/persistence边界和新增工作包为准。
- 没有证据表明需要再安装一套“总控agent”、外部LLM框架或网络服务。游戏核心的NPC选择仍由可测的规则/效用机制承担，Skill只指导开发者。

## 5. 开发任务到已有工具的路由

按每次工作的需要加载少量技能；不要一次把37份全部读进上下文。

| 实际任务 | 已有Skill | 首选工具与验证 |
|---|---|---|
| 进入项目、选择下一工作包 | `reol-project`、`spec-driven-game-dev` | 仓库文档、代码检索；当前事实查BASELINE，顺序查ROADMAP |
| 写GDScript、规则和数据校验 | `godot-gdscript` | 本地代码工具；API不确定查Context7；Godot导入与规则测试 |
| 时间/跨区/经济/社会架构 | `godot-sim-architecture` | 现有纯模拟与固定种子场景；长期/守恒/精度切换测试，不新建平行世界 |
| 劳动、库存、农业和建造 | `colony-sim-systems` | 现有SimInventory/动作执行器；先规则，再Godot AI观察执行 |
| 地形、地图、流式与资源点 | `open-world-2d`、`godot-tilemap`、`procedural-gen` | 现有world适配；引擎文档、实际可达性及区块测试 |
| NPC目标与计划选择 | `game-ai`、按需`ai-behavior-trees-utility-ai` | 少量候选与可解释记录；先测行为，不为技能名字先装行为树addon |
| 角色成长、装备和交谈 | `rpg`、按需`dialogue-systems` | 现有命令/状态接口；对话展示实际事务，不能用对白绕过库存与权限 |
| 完整存档与迁移 | `save-systems`、`godot-sim-architecture` | WorldSessionSnapshot/SimSaveStore；候选全验、roundtrip及坏档回归 |
| 场景、节点与实例 | `godot-nodes-scenes` | 已连接的Godot AI；写入后导入/运行/日志验证 |
| 面板、选中、反馈和音频 | `godot-ui-control`、`game-ui-ux`；按需`game-feel`/`godot-audio` | 现有主题/绘制；Godot AI截图、日志与交互验证 |
| 测试、回归与性能 | `godot-verify`、`godot-gdscript-headless-testing`、按需`performance-optimization` | `tools/godot.py`、现有runner、Godot Profiler；测量后改热点 |
| 图像资源、图集和许可清单 | `create-game-assets`；按需宿主`imagegen` | 先素材brief/来源清单；现有代码绘制、Pillow预览；生成能力和具体素材另验 |
| Windows导出与发包 | `godot-export` | Godot官方模板/导出预设、独立包实际运行；不是当前已验证能力 |
| Codex工具本身排错 | 系统`openai-docs`、按需插件管理 | 官方文档、脱敏本地核对；不顺便更改全局模型/权限 |

Godot AI适合当前编辑器状态、场景检查和运行观察；备用Godot MCP适合独立引擎/项目元信息与必要的无头操作；常规自动测试优先已有本地runner。三条路径无需每次重复执行同一项操作，也不要为了验证把正在使用的编辑器反复停止。

## 6. 真正的缺口和后续选择

| 发现 | 影响 | 最小处理 |
|---|---|---|
| 当前没有`export_presets.cfg`，标准用户模板目录未发现4.7.2导出模板 | 不足以宣称可以发布独立游戏包；可能存在未检查的自定义模板路径 | 到导出工作包核对官方同版本模板、建立Windows预设、实际导出运行；本轮不安装 |
| 当前Python无法导入gdtoolkit | 没有本轮证据支持“已接GDScript lint/format” | 现有Godot解析/测试继续使用；只有出现明确格式/静态分析收益才申请固定版本，不阻塞玩法 |
| 历史TOOLCHAIN含迁移时测试数与临时证据 | 容易被误当作当前玩法完成度 | 工具历史保留；当前功能/测试只以BASELINE为准，本审计记录新调用范围 |
| `npx -y`会按pin值启动备用MCP，缓存丢失时可能需要下载 | pin了包版本，不等于已做到完全离线可复现 | 当前缓存和调用已核实；若要求离线工具包，再单独设计缓存/锁定交付，不能临时改全局npm配置 |
| 通用技能有少量与当前世界契约不同的示例 | 直接复制会丢时间或另建状态所有者 | 按第4节的项目约束覆盖，后续可独立修订技能，保留上游来源 |
| 完整世界源汇、长时/多种子与精度切换压测尚需扩展 | 多装MCP不能证明模拟正确或性能达标 | 按长期方案增加项目自己的场景与诊断；不用外部LLM代替验证 |

现有`addons/`没有GUT、LimboAI、Beehave、Dialogue Manager或Phantom Camera。它们可作为未来明确问题的候选，但当前自有测试runner、简单执行器与相机已成立，**不建议仅为“工具齐全”成套安装**。如果某个工作包确实受益，再核对当时的Godot兼容版本、许可证、维护情况及移除成本，按项目依赖规则处理。

当前不缺一个新的通用Skill库。更有价值的后续沉淀是：把已经跑通的守恒/长期推进验证，和实际采用的素材许可/图集导入流程，分别做成小型项目工作流；流程尚未跑通前不先写成空Skill。

## 7. 复核入口

- 本地只读环境：`python tools/godot.py doctor`。
- 本地项目配置形状：`python tools/setup_codex.py --check`；它只核对预期的项目条目，**不证明全局Godot AI已连接**。
- 实际会话连接：Godot AI读编辑器状态/会话；备用MCP读版本；Context7解析并查询选定Godot文档分支。
- `tools/setup_codex.py`只补缺失项目条目，同名命令/路径/地址冲突会报错并保留原条目，正常写入有备份；不是全局配置修复器。本轮只执行`--check`。
- `tools/mcp/godot_mcp.py`解析现有引擎路径并启动固定0.1.1包，Windows隐藏窗口时显式传递标准流；本轮未改此封装。
- 文档/资源引用：`python tools/check_structure.py`。玩法、画面和发布分别按自己的工作包验收，不能由这一份工具审计替代。

当前最合适的选择是继续使用已核实的工具，把开发时间投入玩法与证据；资源和插件采购/安装仅在确定用途后进行。
