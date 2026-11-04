# Reol AI开发套件：实际配置与验收

2026-11-04。用户已授权本轮测试和调整，并清除原完整游戏Goal；只配置开发设施，不恢复玩法实施。选型依据见[竞品研究](AI-TOOLKIT-REVIEW.md)，组件来源与常规更新见[维护文档](TOOLING-MAINTENANCE.md)。本页记录实际落地，覆盖此前“只调研/未升级”的时点结论。

## 当前采用的组合

| 层次 | 实际采用 | 归属和职责 |
|---|---|---|
| 编码与协调 | 原Codex，全局模型/权限保持 | 文件、检索、Git、命令、子代理；项目级Godot AI审批单独配置，未另装聊天插件或更换客户端 |
| 引擎 | 当前Godot4.7.2，未来跟进最新稳定版 | 本机与当前CI版本明确；不自动下载dev/RC，也不因工具升级改变引擎 |
| 实时编辑器 | **Godot AI插件/后端4.4.1** | 插件在项目`addons/godot_ai/`，认证attach基础条目由官方配置器写用户级Codex配置；MIT，源commit `643c64f3edf984a9668b3043f4d20ebb2bbec6b6` |
| Python工具启动器 | **uv/uvx0.13.7** | 官方Windows发行包；版本目录在本机工具目录，Godot优先查找的用户`.local/bin`也同步为同版；旧程序已备份，未改Langflow自己的目录/安装收据 |
| 文档 | Context7启用，官方文档为核验依据 | 项目级远程连接，当前实际查询Godot文档成功 |
| 备用MCP | Coding-Solo0.1.1默认禁用 | 保留包装器/来源；需要时`python tools/setup_codex.py --enable-backup-godot`，不用时关闭 |
| 无关文档MCP | LangChain仅Reol停用 | 用户级连接保留，项目只继承后设置`enabled=false`，其他项目不变 |
| 技能 | 37项原能力文件保留 | 31项上游只缩简介，6项自有入口修正并分层；不再叠GodotPrompter或额外框架 |
| 验证 | 原项目CLI/runner、Python工具测试、GitHub CI、实际运行/截图 | 不引入GUT/GdUnit4或全仓自动格式化，不改变游戏规则来迁就工具 |

未加入NPGameDev、Swallowtail、FirLab、Serena或商业插件：当前桥恢复并通过所需工作流，不增加重复维护层。它们仍可在出现明确能力缺口时按选型报告对照。

## 配置分层与实际过滤

用户级`~/.codex/config.toml`保存Godot AI官方配对命令与认证attach方式、宿主Node REPL等。只更新Godot AI所需启动器与版本，其余模型、权限和MCP设置经语义比较保持；未把本机配置提交Git。

项目`.codex/config.toml`承担以下覆盖：

- Context7启用，Coding-Solo `godot`禁用。
- `langchain-docs`仅继承禁用，不重复写传输类型。此覆盖要求用户级已有合法同名连接；无继承时不要复制仅`enabled`条目，否则Codex会报invalid transport。
- Godot AI的`disabled_tools`保留四项客户端过滤：`csg_manage`、`gridmap_manage`、`test_run`、`test_manage`。独立Codex进程曾验证生效，但桌面旧子代理仍缓存47项目录，不能以一次成功推断所有宿主都已刷新。
- 本地Godot AI服务器在本项目采用`default_tools_approval_mode="approve"`，对应用户明确授权的本轮/项目编辑器操作；不改变全局审批或系统沙盒。Codex的`auto`按工具注解判断，**不等于总是允许**。曾在只读验收中因注解默认要求审批与`never`冲突而拒绝，改成项目明确授权后新会话实测成功。

生成器`tools/setup_codex.py`仅管理可移植的Context7和备用godot默认值，尊重已有自定义连接/开关，不擅自覆盖继承传输或写Godot AI端口。`--check`只验项目条目，不证明握手；再用`codex mcp list`、`codex mcp get godot-ai --json`及真实调用核对。后两命令可能包含本机路径，分享时脱敏。

为使过滤在客户端之间一致，最后通过Godot公共`EditorSettings` API设置`godot_ai/excluded_domains="csg,gridmap,testing"`，再由官方配置器重新配置Codex，正常退出并重开编辑器。**这项是Godot用户级编辑器设置，会影响使用该编辑器设置的其他项目，不只Reol**；插件源码未改。新的独立认证attach列出43工具，返回这三个排除域，Reol插件/后端4.4.1、ready/stopped。它们移除3D CSG、GridMap及插件自带测试工具，游戏测试继续用原CLI/CI。

需要恢复这些域时，在Godot AI dock的工具域配置中重新勾选并Apply，再Configure Codex并重启客户端；若另一个项目需要3D工具，应先恢复对应域。Reol还须从项目`disabled_tools`移除要恢复的工具；其他项目按各自客户端过滤核对实际目录。旧attach若仍要求空排除列表，会明确返回`NEW_CLIENT_SESSION_REQUIRED`，不能在该旧会话内修复，也不要不断重试旧句柄。

另通过同一公共API设置用户级`godot_ai/auto_reconfigure_clients=false`，关闭普通启停时的客户端自动修复。上游自动修复曾在重开时再次改写旧OpenCode的Godot AI条目；核对仅该条目变化后，恢复其原始备份字节。最终正常停开后，12份其他客户端配置均与备份字节一致，Codex全局其余字段和其他MCP语义一致。日常需要更新连接时主动使用Configure Codex；**上游升级后的自动迁移是独立路径，不保证受此开关控制，未来升级仍须备份并复核其他客户端**。

## Godot AI升级及启动故障的真实处理

1. 备份原插件、用户/项目配置和可能被上游自动重新固定版本的客户端配置，保存在忽略的本机日志目录。
2. 从固定源commit取得官方`script/v4-release`和`src/godot_ai/release_verify.py`，核对源码哈希；验证v4.4.1三件正式发布资产的签名、仓库/channel/tag/version/commit身份、ZIP及325文件完整清单。
3. 正常关闭Reol编辑器后，使用官方闭编辑器`verify`再`install`，得到`OK: installed exact v4 tree 4.4.1`。不是手工覆盖addon；旧4.3.1整树保留于官方更新备份。
4. 第一次重开失败：`The launched process identity could not be captured... now alive=no`。原命令捕获到更早的真实错误：**uv0.9.5不能解析`--exclude-newer-package godot-ai=false`，退出2**。进程早退导致身份捕获失败，不是凭提示就判端口/防火墙。
5. `uv self update`拒绝更新，因为该便携副本的安装收据指向Langflow管理目录。未强改收据或卸载Langflow；改用uv官方0.13.7 Windows压缩发行包，核对GitHub公布SHA256后安装并保留旧程序。只改PATH不足以解决：Godot AI先查已知的`.local/bin/uvx.exe`，因此确认旧uv进程已退出后将该便携副本也更新为同一官方字节。
6. 旧4.3.1后端和旧attach仍占原端口。核对命令、PID、父进程、版本和监听归属，只停止已验证的旧Godot AI进程树；未关闭无关Python或连接器。随后正常重开，4.4.1成功接管。
7. 上游自动配置也曾改写旧OpenCode条目；经备份差异确认只改其Godot AI启动字段后恢复原字节，并关闭上述自动重配设置。最终重启后再次逐字节核对其他客户端保持。Codex的配对pin保留4.4.1。

重要固定证据：

| 对象 | SHA256 |
|---|---|
| Godot AI4.4.1正式ZIP | `aa101a3e8991e95fb2a358cae1aeb06f3550622daea10b366aeda81335a91f7f` |
| 签名公钥SPKI指纹 | `84ebbd811f3a12c09ff4e236bbbbb9310fc23e03fcfc3717ba546747d0d21072` |
| uv0.13.7 Windows x86_64正式ZIP | `0cdc5b38fe5a8168ed6a25814f5ba43c21d313dd3187314fccb37b7cec46e021` |

安装后再次逐项核对：325文件、0哈希差异、0额外文件，未本地修补插件。Godot自动将`project.godot`的两个既有autoload重排，保留相同脚本与键；该引擎生成差异随工具提交。`scenes/boot.tscn`首次保存产生纯序列化变化，已恢复备份，不提交无关场景变化。

## 技能与指令整理

31项第三方技能仅修改`description`，名称、正文和资源保持原pin，许可证/NOTICE保留且注明本地修订。6项自有入口修正旧Demo/锁版入口、预算耗尽丢时间示例、反复全量检查和同步runner误用await，补按需参考。AGENTS收束为当前授权、非显然工程约束、文档入口和路由，历史/领域细节仍留原文档。

| 同一静态计数方法 | 修改前 | 修改后 |
|---|---:|---:|
| 37项名称+description Unicode字符 | 13,217 | 3,556 |
| 37项SKILL正文，统一换行 | 265,852 | 233,811 |
| 37份SKILL完整文件，统一换行 | 280,443 | 238,465 |

这些是文件字符数，**不是token、实际注入量或费用下降比例**；上轮含原始CRLF的统计口径不能直接混比。技能验证器37/37、本地引用32项及15项静态路由样例通过；路由样例不证明模型在所有真实任务上的选择。新Codex会话读取缩减后的目录成功。

## 已完成的本机验收

- Python工具回归33项通过；结构/链接及Git差异检查通过。故意错误与超时样例在Python测试输出出现，但对应测试通过，不是产品报错。
- 新独立stdio进程经**实际官方attach配置**握手，Reol会话插件/后端均4.4.1、ready/stopped；不将MCP初始化里的FastMCP版本当Godot AI版本。
- 创建临时场景、节点和脚本，读属性再改值，保存、离开并重开/强制重载，值保留；未改正式游戏逻辑。
- 运行样本、通过真实Input action时间线输入，观察运行变量与标签变为`input count: 1`；取得1280×720非stale截图并实际查看。
- 写入故意语法错误，工具返回具体Parse Error诊断；修正后诊断清空。`script_create`可能“已写入成功”但diagnostics非空，不能只看顶层is_error。
- 原游戏主入口真实启动，helper_live、1280×720画面已查看，随后正常停止；不因此声称完整游戏验收通过。
- 新Codex进程实际调用session_manage/editor_state成功，确认4.4.1/ready/stopped，四个过滤工具不可见。前两次审批冲突失败记录保留，第三次以项目授权配置通过。

最终域配置正常重启后，独立SDK和第四次全新Codex进程均确认三个排除域、四工具不可见和Reol连接。关闭自动重配后再正常停开，独立SDK仍为43工具、4.4.1、ready/stopped，其他客户端保持原字节。旧桌面子代理仍持旧attach参数，返回`NEW_CLIENT_SESSION_REQUIRED`；这是配置缓存证据，不是新后端未启动。早期编辑器进程累计日志含本轮故意坏语法样例，因此退出时包装器返回1；该输出保留，不能拿它声称整段编辑器日志无错误。后续域/偏好配置这一整次编辑器运行退出0，日志`editor-20261104-094141.log`。

截图见[临时输入样本](qa/20261104_toolkit_sample.png)和[原游戏入口](qa/20261104_toolkit_main.png)。详细本机日志、配置备份和临时场景在忽略的`logs/toolkit_setup_20261104_090447/`，探针场景已关闭并归档，不随游戏分发。

已发现工具边界：游戏运行时截图附带`save_to`会被当作编辑器写入而拒绝；使用不带该参数的图片响应，客户端保存原PNG即可。本轮样本最初用`is_action_just_pressed`未观察到合成边沿，改为按帧采样pressed状态后观察到一次输入；不把此样本成功推广为所有热键/前摇时序已验。新的scene close参数是`discard_changes`，旧参数会明确报错。均未为此修补第三方源码。

## CI与剩余边界

工具提交`0ecae3a`已推。核查旧U3-b1 run41742281428发现三项历史测试前提错误，均早于本轮设施升级：两项期待旧artifact v4但明确迁移为v5；另一项临时旧root夹带现代artifact版本而被正确拒绝。

测试修正提交`0804c70`只改临时构造与迁移期望，仍全字典比较，增加混版拒绝/活世界不变检查，不改真实fixture或游戏逻辑。三项定向704断言/0失败；完整CI为[run41755190941](https://github.com/fewnfds/reol/actions/runs/41755190941)，结果以实际完成后BASELINE为准，运行中不算绿色。

当前旧聊天/旧子代理的MCP句柄仍可能Transport closed；新Codex进程已验证成功。**完成后重启Codex一次**以刷新本聊天/后续子代理的启动命令和过滤目录；不需重装Godot。启动后先核Reol的session版本和状态，不能把旧句柄失败当新版后端已停止。

回退：保留本机旧配置/uv压缩备份及官方addon旧树；只在确认版本、进程和目标路径后按官方恢复流程还原配套组件。回退插件与后端要成对，不能用裸HTTP绕过认证。本轮未演练故障回退，不保证所有失败能自动恢复。原完整游戏Goal已清除，不因工具配置成功自动恢复。
