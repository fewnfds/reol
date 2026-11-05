# Reol AI开发套件：实际配置与验收

本页记录项目工具配置与使用边界；实际会话仍需核对，工作授权和停点见[HANDOFF](../../status/handoff.md)。选型方法见[竞品研究](evaluation.md)，组件来源与更新见[维护文档](maintenance.md)。

## 当前采用的组合

| 层次 | 实际采用 | 归属和职责 |
|---|---|---|
| 编码与协调 | 原Codex，全局模型/权限保持 | 文件、检索、Git、命令、子代理；项目级Godot AI审批单独配置，未另装聊天插件或更换客户端 |
| 引擎 | 当前Godot4.7.2，未来跟进最新稳定版 | 本机与当前CI版本明确；不自动下载dev/RC，也不因工具升级改变引擎 |
| 实时编辑器 | **Godot AI插件/后端4.4.1** | 插件在项目`addons/godot_ai/`，认证attach基础条目由官方配置器写用户级Codex配置；MIT，源commit `643c64f3edf984a9668b3043f4d20ebb2bbec6b6` |
| Python工具启动器 | **uv/uvx0.13.7** | 官方Windows发行包；版本目录在本机工具目录，Godot优先查找的用户`.local/bin`也同步为同版；旧程序已备份，未改Langflow自己的目录/安装收据 |
| 文档 | Context7启用，官方文档为核验依据 | 项目级远程连接；按目标版本核对官方说明 |
| 备用MCP | Coding-Solo0.1.1默认禁用 | 保留包装器/来源；需要时`python tools/setup_codex.py --enable-backup-godot`，不用时关闭 |
| 无关文档MCP | LangChain仅Reol停用 | 用户级连接保留，项目只继承后设置`enabled=false`，其他项目不变 |
| 本地代码审查 | 项目审查模型Sol；公司`custom`路由 | 由主代理按工作包调用原生review，GitHub云端模型审查未开启；使用方式及费用边界见[审查工作流](../workflow/code-review.md) |
| 技能 | 项目技能按需读取 | 具体清单以 `.agents/skills/` 为准，保留第三方来源和许可；不叠加用途重复的框架 |
| 验证 | 原项目CLI/runner、Python工具测试、GitHub CI、实际运行/截图 | 不引入GUT/GdUnit4或全仓自动格式化，不改变游戏规则来迁就工具；提交审查采用[原生Codex工作流](../workflow/code-review.md) |

未加入NPGameDev、Swallowtail、FirLab、Serena或商业插件；出现明确能力缺口时可按选型方法作隔离对照。

## 配置分层与实际过滤

用户级`~/.codex/config.toml`保存Godot AI官方配对命令与认证attach方式、宿主Node REPL等。只更新Godot AI所需启动器与版本，其余模型、权限和MCP设置经语义比较保持；未把本机配置提交Git。

项目`.codex/config.toml`承担以下覆盖：

- Context7启用，Coding-Solo `godot`禁用。
- `langchain-docs`仅继承禁用，不重复写传输类型。此覆盖要求用户级已有合法同名连接；无继承时不要复制仅`enabled`条目，否则Codex会报invalid transport。
- Godot AI的`disabled_tools`保留四项客户端过滤：`csg_manage`、`gridmap_manage`、`test_run`、`test_manage`。客户端可能缓存旧目录，需核对当前实际连接。
- 本地Godot AI服务器在本项目采用`default_tools_approval_mode="approve"`，对应项目编辑器操作的授权范围；不改变全局审批或系统沙盒。Codex的`auto`按工具注解判断，**不等于总是允许**。

生成器`tools/setup_codex.py`仅管理可移植的Context7和备用godot默认值，尊重已有自定义连接/开关，不擅自覆盖继承传输或写Godot AI端口。`--check`只验项目条目，不证明握手；再用`codex mcp list`、`codex mcp get godot-ai --json`及真实调用核对。后两命令可能包含本机路径，分享时脱敏。

另外可以通过显式参数`--review-model gpt-6.1-sol`设置项目根级审查模型；不传参数时不会改已有审查模型。与`--check`结合只做核对，具体记录和CLI命令见[审查工作流](../workflow/code-review.md)。它不修改主模型、全局provider或权限。

通过Godot公共`EditorSettings` API设置`godot_ai/excluded_domains="csg,gridmap,testing"`，再由官方配置器重新配置Codex。**这项是Godot用户级编辑器设置，会影响使用该编辑器设置的其他项目，不只Reol**；插件源码未改。它们移除3D CSG、GridMap及插件自带测试工具，游戏测试继续用原CLI/CI。

需要恢复这些域时，在Godot AI dock的工具域配置中重新勾选并Apply，再Configure Codex并重启客户端；若另一个项目需要3D工具，应先恢复对应域。Reol还须从项目`disabled_tools`移除要恢复的工具；其他项目按各自客户端过滤核对实际目录。旧attach若仍要求空排除列表，会明确返回`NEW_CLIENT_SESSION_REQUIRED`，不能在该旧会话内修复，也不要不断重试旧句柄。

用户级`godot_ai/auto_reconfigure_clients=false`关闭普通启停时的客户端自动修复。日常需要更新连接时主动使用Configure Codex；**上游升级后的自动迁移是独立路径，不保证受此开关控制，未来升级仍须备份并复核其他客户端**。

## 启动故障和回退

启动失败先核对实际进程、最早的错误、工具与插件/后端版本及当前会话；旧客户端缓存或旧 attach 报错不等于当前后端已停止。连接需要刷新时按官方 Configure 和客户端提示重载，勿反复使用失效句柄。

回退前核对版本、进程和目标路径，按官方流程成对恢复插件、后端及原连接；保留本机备份，不能用裸 HTTP 绕过认证。完整的升级经过、历史验证和限制见[历史记录](../../archive/engineering-context-20261105/tooling-setup.md)。
