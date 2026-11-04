# AI开发基础设施：来源、更新与上下文预算

> **文档角色：** 更新来源、维护方法和2026-11-04升级前研究快照；历史表格及“尚未升级”“下一步升级”等措辞只描述当时，不是现在的待办。Godot AI 4.4.1已随后配对安装与验收，现状以[AI开发套件实装追踪](AI-TOOLKIT-SETUP.md)为准；审查模型和CI观察以[审查工作流](CODE-REVIEW-WORKFLOW.md)为准。

核对日期：2026-11-04。本文记录实际安装和官方上游查询，供之后维护；版本结论会过期，更新前须重查。游戏开发Goal已由用户暂停，本轮只研究、读取状态和整理文档，没有升级插件、安装候选、修改本机连接配置或启动游戏。唯一第三方分发补充是保留已有技能库同一固定提交的NOTICE，不是升级技能。

后续扩展的[套件选型/风评与竞品研究](AI-TOOLKIT-REVIEW.md)比较了实时MCP、CLI、GodotPrompter、语义/测试工具与独立反馈。用户已澄清未来跟进Godot最新版，建议以最新稳定版为目标，4.7.2只是当前验证点；此澄清覆盖此前永久锁版表述，未执行升级。

**建议继续使用Codex + 一个Godot编辑器MCP + Context7 + 原命令行/CI。** 优先评估现有Godot AI从4.3.1配对升级至4.4.1，精简工具域和技能路由；现有技能上游没有新版本需要同步。候选工具先做同任务比较，不按工具数量、星数或演示视频换栈。

## 1. 研究时点安装、配置归属和更新来源

| 组件 | 实际现状 | 本次查到的上游 | 配置/维护者与结论 |
|---|---|---|---|
| Godot Engine | 4.7.2，doctor及编辑器返回一致 | 当前最新稳定版为4.7.2，未来跟进稳定发布 | 每次采用具体版本并验插件/CI/导出模板；此轮不改引擎或导出模板 |
| Godot AI插件与后端 | `addons/godot_ai/plugin.cfg`、实际会话均4.3.1 | [稳定4.4.1](https://github.com/hi-godot/godot-ai/releases/tag/v4.4.1)，2026-11-03发布；[PyPI后端](https://pypi.org/project/godot-ai/4.4.1/)亦4.4.1 | 插件随项目Git；后端由dock生成的全局`~/.codex/config.toml`精确pin、uvx启动。MIT；值得做受控配对升级，尚未执行 |
| Coding-Solo Godot MCP | 包装器固定`@coding-solo/godot-mcp@0.1.1` | [npm registry](https://registry.npmjs.org/%40coding-solo%2Fgodot-mcp) latest仍0.1.1，2026-02-03发布 | 项目`.codex/config.toml`→[包装器](../tools/mcp/godot_mcp.py)。[上游](https://github.com/Coding-Solo/godot-mcp)MIT，最近push为2026-04-16；当前无包升级，适合作备用 |
| Context7 | 项目连接`https://mcp.context7.com/mcp` | [上游](https://github.com/upstash/context7)仍维护；可选本地npm包4.5.0 | 当前是远程服务，不是本地npm安装，无法据npm版本推断远端部署；没有需要执行的本地升级 |
| 游戏开发第三方技能 | 31项、77文件；固定`19d93f97c9c1ea0f8b306e77aa81e0d3e352d3e9` | [上游main](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)本次仍为同一提交，2026-10-28 | 项目`.agents/skills/`，Apache-2.0；逐文件统一换行后内容一致，无上游增量需要同步 |
| Reol自有技能 | 6项、10文件 | 本项目维护 | `reol-project`、`godot-sim-architecture`、`godot-verify`、`colony-sim-systems`、`open-world-2d`、`spec-driven-game-dev`；须跟现有代码/流程维护，不能拿第三方更新覆盖 |
| Codex客户端/内置能力 | 当前终端`codex --version`为0.166.0-alpha.6 | [CLI稳定发布](https://github.com/openai/codex/releases/tag/rust-v0.166.0)为0.166.0 | 桌面应用、它托管的CLI与独立安装CLI可能是不同渠道；走各自官方更新入口，不用npm安装另一份来“修复”桌面版本 |
| 系统/插件技能、浏览器、Node REPL | 由宿主暴露；全局`node_repl`命令指向Codex自带运行时，项目未复制 | 随Codex及所装插件维护 | 系统技能、插件缓存和Node REPL由宿主管理；不另装同名npm包替代，不手工修改`~/.codex/plugins/cache/`或把缓存复制进游戏仓库 |
| LangChain文档MCP | 全局`langchain-docs`连接`https://docs.langchain.com/mcp` | [LangChain官方文档服务](https://docs.langchain.com/)远程维护，未暴露可核对的服务版本 | 无本地包可升级；与当前GDScript开发无直接关系，可考虑仅在本项目停用。本轮没改全局设置 |
| 个人其他技能 | Office/SAP等另在用户技能目录 | 各自维护者，不归Reol的37项技能 | 本轮未逐项升级或审计其第三方运行依赖；如要用，按各技能声明的官方来源单独维护，不把本项目31项上游pin用于它们 |

项目`.codex/config.toml`只含本机路径/连接，已忽略；共享的配置生成逻辑是[setup_codex.py](../tools/setup_codex.py)。`opencode.json`只是旧客户端配置。全局与项目配置分层，名字不同的两个Godot服务器并非同一安装，但功能有重叠。完整位置说明见[旧审计](DEVELOPMENT-TOOLS-AUDIT.md)，其中2026-11-02数字属于历史。

`uv tool list`本次显示没有安装工具，不能据此判Godot AI缺失：它由精确版本的`uvx --from godot-ai==…`隔离环境运行。直接在默认Python执行`pip show`同样不能证明这个后端是否安装。

## 2. Godot AI怎样升级

4.4.0新增AnimationTree、音频总线、资源/导入设置和截图能力，并修复脚本验证缓存、场景写入等问题；4.4.1主要调整固定运行依赖。日期应区分：CHANGELOG的4.4.1条目标2026-11-02，GitHub/PyPI实际发布为11月3日。[版本日志](https://github.com/hi-godot/godot-ai/blob/v4.4.1/CHANGELOG.md)

上游声明Godot 4.7+的4.x及Python >=3.11,<3.15，本机在范围内。这里只证明符合声明，不证明新版本在Reol已通过。当前4.3.1已经包含其当时FastMCP修复，不应把所有安全修复都归到4.4.1。

1. **选定版本。** 重查稳定release、版本固定的迁移说明和已知问题，保存当前Git提交及本机连接条目的可恢复副本。备份含本机路径或凭据时只留本机，不上传。升级与新候选按[AGENTS](../AGENTS.md)的依赖规则办理。
2. **插件与后端成对更新。** 通过Godot AI dock支持的Update/官方安装流程更新，不手改`addons/`，不混覆盖文件，不只改uvx pin。发布的[迁移指南](https://github.com/hi-godot/godot-ai/blob/643c64f3edf984a9668b3043f4d20ebb2bbec6b6/docs/v4-migration.md)与[更新器说明](https://github.com/hi-godot/godot-ai/blob/v4.4.1/docs/self-update.md)是入口。
3. **重新核对客户端。** 用dock的Configure → Codex生成匹配版本、端口、工具域和attach命令；先看它会改哪个范围。全局Godot AI条目可能影响其他仍用旧插件的项目。4.x使用`godot-ai attach`认证桥，不能擅改成裸HTTP地址。
4. **重载后验连接。** 新版更新器支持若干热切换/复验，但不能据此保证旧4.3.1的升级流程无需重启。按实际提示刷新或重启编辑器/Codex，确认`session_manage`返回的插件与后端同为目标版本、项目路径正确、editor ready。
5. **验实际工作流。** 先读场景树/脚本/日志，再在可丢弃场景试节点写入、保存与撤销；运行主局，检查helper live、日志和1280×720截图。原`python tools/godot.py check`仍走CI，不重复多开本地全套。升级工具不能代替产品回归。
6. **记录与回退。** 记录release、实际版本、许可、配置范围及证据，提交官方更新产生的插件差异。失败先看更新日志与保留旧树；必要时关闭编辑器，按官方恢复流程还原整套插件及原连接pin，再验会话。签名/哈希通过不等于项目能解析；不假定每种失败都会自动回滚。

## 3. 其他组件怎样维护

| 对象 | 检查与更新方式 | 必须保留的东西 |
|---|---|---|
| Coding-Solo | 先只读查询npm latest、变更与许可；真有需要再改包装器`PACKAGE`固定版本并验证握手/版本/项目查询 | 旧pin、包装器Windows标准流处理、配置生成测试；不换成`@latest` |
| Context7 | 保持远程URL，查官方服务/连接/认证说明；改用本地包是另一个方案，不是例行升级 | 原连接配置和最小查询；不把项目私密代码放进文档查询 |
| 31项上游技能 | 对比旧pin、本地内容和新pin，按实际选用目录三方合并；更新第三方来源提交和修改说明 | LICENSE、适用NOTICE、附带references/scripts、自己的局部修订；不整库复制新增技能 |
| 6项自有技能 | 对照当前AGENTS、代码所有者和验证流程做小改，测试任务能否正确触发 | 非显然项目约束和权威入口，不保留已过时“下一包”与旧Demo阶段 |
| Codex系统/商店插件 | 从桌面应用/插件管理官方入口更新，核查其新增技能、MCP、权限和依赖；更新后重查实际可用能力 | 用户其他项目设置；不手改插件缓存、自动全开新工具或替换全局模型 |
| Godot本体/运行环境 | 跟项目明确版本，分别更新；插件小升级不捎带升级引擎、Python或Node | 可复现版本、导出模板匹配、CI下载哈希；已有环境正常时不一起换栈 |

只读检查示例，均不会执行安装：

```powershell
python tools/godot.py doctor
python tools/setup_codex.py --check
codex --version
codex mcp list
gh api repos/hi-godot/godot-ai/releases/latest --jq '{version:.tag_name,published:.published_at,url:.html_url}'
npm view @coding-solo/godot-mcp version
gh api repos/gamedev-skills/awesome-gamedev-agent-skills/commits/main --jq .sha
```

`enabled`、`Auth: Unsupported`、配置文件存在都不等于握手成功或失败。用当前工具实际调用验证；个别会话`Transport closed`须检查该连接与会话状态，不据此重装所有服务。

## 4. 几十个Skill是否占很多提示词

**有开销，但通常不是37份正文一起常驻。** Codex先用名称、description和路径发现技能，选中才读`SKILL.md`，参考文件再按需读。当前官方说明还给发现目录设默认预算：模型上下文的2%，未知容量时为8,000字符；目录过大先缩短描述，仍过大可能略去部分项并提示。`skills.max_context_tokens`可调整发现目录预算，但不限制选中后正文的大小。[官方机制](https://learn.chatgpt.com/docs/build-skills)、[配置项](https://learn.chatgpt.com/docs/config-file/config-reference)

本次对项目文件的静态计数：

| 范围 | 实际规模 | 应怎样理解 |
|---|---:|---|
| 37项名称+简介的值 | 13,217 Unicode字符 | 不含路径和宿主包装，也不含项目外技能；实际宿主可能缩短描述 |
| 37份SKILL正文合计 | 270,478字符 | 只有实际选用/读取的内容进入后续上下文，不能当作启动注入量 |
| 全技能目录87文件 | 597,979字节 | 含references/assets；磁盘大小不是上下文大小 |
| 最长简介 | 718字符 | 28项简介超过200字符，存在精简余地；不单凭长短判技能质量 |

**字符、字节和token不能互换。** 本轮未使用模型tokenizer或宿主prompt trace，不能给出精确token占用/费用或宣称节省百分比。项目外系统/个人/插件技能也会影响目录预算。

建议保留技能文件，把使用方式收束为：入口`reol-project`；写代码用`godot-gdscript`；跨域/时间/存读用`godot-sim-architecture`；验收用`godot-verify`。新大包才加`spec-driven-game-dev`，其余地图、UI、NPC、动画、导出等按实际需要取1–3项，绝不每次读完四项或全部37项。通用UI与Godot Control、通用AI与行为树、通用物理与Godot物理要分清触发边界。

本次发现更值得处理的是自有规则过时：`reol-project`仍指早期Demo和方向稿，模拟架构例子允许丢掉未处理时间，部分流程技能倾向反复全套检查。这些与当前项目合同不同，后续应局部修正；本轮没有改技能。第三方技能例子不是对当前已验证系统的自动重写授权。

如以后需要禁用，官方支持`[[skills.config]]`及`enabled=false`，也有明确调用的policy选项；先核对安装客户端实际支持的配置形式。**禁用与删除不同，禁止把目录预算调小就当精简成功。** 预算太小可能使必需技能不在初始目录；`allow_implicit_invocation=false`也不能未经验证就当作移除了目录开销。先精简description和入口，再决定是否按项目停用不相关项。[官方配置参考](https://learn.chatgpt.com/docs/config-file/config-reference)

## 5. MCP、日志和长文档的成本

本轮宿主导出的Godot AI目录是47个工具，其description字符串合计94,238字符；Coding-Solo 14个、Context7 2个。**这是可导出的目录文本，不是证明这些全文都在每轮prompt中。** 当前环境支持延迟发现，具体注入、缓存和计费由宿主决定；不能直接换算成“每轮浪费多少token”。MCP协议自身也不保证任何客户端都按需加载。

更有效的做法：

- 在Godot AI dock的Tools域选择中，常用保留editor（含日志/截图）、scene/node、script、project/game、filesystem、api、batch；需要的resource/UI/tilemap按任务开。纯2D项目可先考虑关`csg`、`gridmap`；音频/材质/粒子等正在做时再开，不按“3D”猜域名。配置后由dock重新Configure，再看`exclude_domains`和实际工具目录。目前仍是全域开启，本轮没有改。
- 全局LangChain文档连接对Reol可考虑项目级停用；备用Coding-Solo也可只在需要独立引擎进程时启用。保留原配置，不影响其他项目。原命令行已经承担大量导入/回归工作，不需要再增同类MCP。
- 用`enabled_tools`/`disabled_tools`可过滤Codex的MCP工具，但要保留当前需要的运行、停止、日志和截图链，不能过滤后失去验收能力。选域后实际重连验证；不把API的`defer_loading`参数照搬进Codex TOML。[Codex MCP配置](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)
- 日志用cursor/尾部/首错，场景树分页，截图只在可见验收时取；少量API精确查询优于整项目全文导出。工具数量少但每次返回几十万字符，同样会挤占上下文。
- 当前HANDOFF、BASELINE、FEATURES各有大量历史。以本次变更前快照计，三者约8,224/23,909/22,621字符；若反复全读，可能比技能目录更浪费。应让当前摘要短、领域文档按需读，历史留QA/归档；这是下一轮文档整理建议，本轮不删历史或大改启动规则。

Godot AI本身已有核心工具+领域合并工具和按需资源设计；“120+操作”与“47工具”不是同一计数单位。[工具设计](https://github.com/hi-godot/godot-ai/blob/v4.4.1/docs/TOOLS.md)、[可选域目录](https://github.com/hi-godot/godot-ai/blob/v4.4.1/plugin/addons/godot_ai/tool_catalog.gd)。

## 6. 精选替代方案

下表均是官方项目资料和发布信息，**没有在Reol安装或做性能/成功率对照**。出现在Godot商店/资源库的是社区工具，不因此成为Godot官方开发工具。

| 方案 | 值得比较的地方 | 限制与建议 |
|---|---|---|
| 继续使用[Godot AI](https://github.com/hi-godot/godot-ai) | 已在本项目实测编辑器/运行/日志/截图，有4.4.1维护版本；MIT | 首选。先配对升级和裁工具域；现有项目收益确定，换栈收益未证实 |
| [NPGameDev Toolkit + Server](https://github.com/NPGameDev/godot-mcp-toolkit) | 插件与Node桥均有v1.1.2（2026-10-29）；[源码MIT，品牌素材另有限制](https://github.com/NPGameDev/godot-mcp-toolkit/blob/v1.1.2/LICENSE)。按组发现、GDScript扩展、运行/LSP能力，并公开目录规模测量 | 可作首个对照候选，仍需两个组件。上游测量以bytes/4估token，不是本项目的真实计费。其2026-10-24快照startup36工具约38KB，不能仅凭“按需”判断一定比现有小。[测量方法](https://github.com/NPGameDev/godot-mcp-server/blob/main/docs/token-efficiency.md) |
| [FirLab / sunerpy godot-mcp](https://github.com/sunerpy/godot-mcp) | v0.2.0（2026-11-03），MIT；Rust MCP主程序搭配supervisor及桥接资源整包发行，默认只读core、无引擎静态分析、带哈希的事务编辑和运行捕获 | 可作第二个对照候选。新版本阶段，分析推断不等于引擎真值；实际编辑器能力仍涉及addon，不能理解为零集成成本。上游发布CI仅核到Godot4.7.1，Reol4.7.2兼容尚未证明。[官方说明](https://firlab.app/godot-mcp/) |
| [Godot官方LSP/DAP](https://docs.godotengine.org/en/4.7/tutorials/editor/external_editor.html#lsp-dap-support) | 跟引擎的补全/诊断/调试协议，Godot MIT；可补符号查询和调试 | 不是另一套MCP，也不替代运行、画面和场景编辑；需兼容客户端。优先利用已有能力，再考虑桥接 |

另外查看过[原生Godot MCP](https://github.com/yurineko73/Godot-MCP-Native)和[Fennara](https://github.com/fennaraOfficial/fennara-godot-ai)：前者原生服务/可选CLI，后者重工作树/daemon；都与现有工具重叠，当前没有独有需求促使加入。无需为了收集工具把它们常驻。商业工具如GDAI也未因功能宣传而进入采购/安装清单。

若要比较，固定同一份隔离检出、当次目标引擎具体版本（目前4.7.2）和任务：①找跨脚本调用，②改一个场景并保存/撤销，③启动→真实输入→日志→截图，④运行坏脚本读首错，⑤中断/重启后重连。记录结果正确性、失败恢复、总调用/输出量、时间和本机内存。一次只连一套写编辑器的MCP，不让两个代理抢写同一场景；原方案保留为回退。不用上游自己的bench直接宣称“更优质”。

## 7. 本轮证据与后续顺序

已执行：doctor、配置只读检查、CLI版本、本机脱敏配置归属读取、37项技能结构和上游77文件比较；GitHub/PyPI/npm官方元数据查询；根会话Godot AI会话/编辑器只读查询成功，返回编辑器ready、游戏stopped、插件/后端4.3.1、exclude_domains为空。子代理两次调用均`Transport closed`，其中一次在根会话成功之后；跨会话稳定性尚未确认，未为此重启服务。

编辑器日志仍能读到此前的脚本类注册错误；没有把“连接正常”写成“编辑器无错”，也没有验证新版一定修复这些项目/缓存问题。没有执行新版写操作、升级、回退演练或候选本机评测。

研究当时建议先验证Godot AI配对升级和精简技能/工具域；这些后续已执行，具体证据与仍有限制见[套件实装](AI-TOOLKIT-SETUP.md)。将来只有出现具体能力缺口时才另选候选做隔离对照；技能目录或连接在当前客户端未刷新时再重载或重启，不能以此历史研究判断游戏Goal状态。
