# 工具配置与维护

类型：工具记忆，故障/升级时查询。运行命令在[usage](usage.md)，agent载入机制在[DOCUMENTATION](../../DOCUMENTATION.md)；本页不规定每包检查工具或调整模型。

## 当前分工

| 组件 | 用途与边界 |
|---|---|
| Codex + 文件/CLI | 改代码、查Git、运行命令；现有路由/权限由宿主与本机配置管理 |
| Godot AI | 单个已核对项目的实时场景、运行、日志、输入与截图；用官方dock Configure生成认证attach，不猜端口或裸HTTP |
| Context7 | 查询目标版本文档；可用性依实际会话，没有该工具时使用官方文档 |
| Coding-Solo | 默认关闭的备用连接，不与主连接叠写同一编辑器 |
| 项目skills | 仅提供Reol特有的模拟接入、验证排错与二维素材操作；不代替默认编码约定 |
| 原生review | 可按具体需要手动使用，已有项目模型配置不意味着每包自动执行 |

Godot、插件、技能/工具各有采用版本；实际引擎只登记在[BASELINE](../../status/baseline.md)，第三方pin/许可按[NOTICES](../../../THIRD_PARTY_NOTICES.md)维护。不因文档旧版本示例自动升级或安装依赖。

## 配置在哪里

项目`.codex/config.toml`是忽略的本机覆盖，可配置Context7、备用godot及工具过滤。用户级配置保存官方Godot AI认证条目和其他项目的连接；不要将原文件/备份上传仓库。`tools/setup_codex.py`只管理其声明支持的条目，保留已有自定义；`--check`是配置核对，不证明握手。

Godot AI的用户级域过滤可能同时影响其他项目。恢复`csg/gridmap/testing`等域时从官方dock调整并重新Configure，核对本项目客户端过滤和新会话；不为修Reol擅自改变其他项目配置。旧attach失效或返回`NEW_CLIENT_SESSION_REQUIRED`时按实际提示重连，不重复使用坏handle。

## skills怎样维护

项目在`.agents/skills/`只维护三个入口；名称/描述供宿主选择，正文按任务需要读取，不要求每次全读。

| 入口 | 使用范围 / 保留的专门知识 |
|---|---|
| [godot-sim-architecture](../../../.agents/skills/godot-sim-architecture/SKILL.md) | 模拟功能的owner、访问形状、跨步采用与恢复；接入原框架，避免套每NPC一个Node的教程 |
| [godot-verify](../../../.agents/skills/godot-verify/SKILL.md) | 相关短验证及headless导入、异步、错误退出/挂起排错 |
| [create-game-assets](../../../.agents/skills/create-game-assets/SKILL.md) | 纯二维斜俯视、脚点/图集接入；Pillow透明/尺寸/色数报告与联系表脚本 |

原36个入口中的通用Godot API、游戏类型、跨引擎调优教程已移除；自有工作/世界接续/范围收敛提示并回模拟接入及原工程流程，headless排错并入验证技能。素材技能删除三维流程和重复台账模板，沿已有资产清单维护。原通用资源引用检查器没有仓库代码/工具调用方；当前检查由`tools/check_structure.py`及实际Godot导入/运行负责，不再分发第二个入口，两者并非完全相同的检查器。

清理依据是内容适配、重复与可执行工具价值；没有使用遥测，不能据此认定某技能从未使用或导致了某个缺陷。入口减少只降低选择噪声，质量仍由[默认约定](../../../AGENTS.md#实现与review先检查访问规模)与[写前/review流程](../workflow/testing.md#写前设计与代码review)负责。

新增技能前先确认：是否有跨任务复用、模型不易直接推知的项目知识或可靠工具，是否能并入已有入口；单纯API说明、目录导航或当前任务不独立建skill。新能力的API按需查目标版本官方资料。宿主/system/plugin及用户个人技能由各自官方入口维护，本次只清理项目目录。

## 更新或恢复时

先定位实际故障和所属组件，再核对上游稳定release、兼容与许可，保存可恢复配置。Godot AI使用官方插件整树与配置流程，技能更新保留来源与自有修改；不把引擎、MCP、模型和权限打包一起换。只有真实调用/输出能证明相应能力，文件存在或`enabled`不能证明握手。

旧更新清单、Node/CI迁移和竞品评估已进[tooling归档](../../archive/README.md)，不继续执行旧步骤。
