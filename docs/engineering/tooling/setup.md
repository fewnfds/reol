# 工具配置与维护

类型：工具记忆，故障/升级时查询。运行命令在[usage](usage.md)，agent载入机制在[DOCUMENTATION](../../DOCUMENTATION.md)；本页不规定每包检查工具或调整模型。

## 当前分工

| 组件 | 用途与边界 |
|---|---|
| Codex + 文件/CLI | 改代码、查Git、运行命令；现有路由/权限由宿主与本机配置管理 |
| Godot AI | 单个已核对项目的实时场景、运行、日志、输入与截图；用官方dock Configure生成认证attach，不猜端口或裸HTTP |
| Context7 | 查询目标版本文档；可用性依实际会话，没有该工具时使用官方文档 |
| Coding-Solo | 默认关闭的备用连接，不与主连接叠写同一编辑器 |
| 项目skills | 通用技能提供方法，自有技能提供窄范围定位；不复制基础规则或当前计划 |
| 原生review | 可按具体需要手动使用，已有项目模型配置不意味着每包自动执行 |

Godot、插件、技能/工具各有采用版本；实际引擎只登记在BASELINE，第三方pin/许可按[NOTICES](../../../THIRD_PARTY_NOTICES.md)维护。不因文档旧版本示例自动升级或安装依赖。

## 配置在哪里

项目`.codex/config.toml`是忽略的本机覆盖，可配置Context7、备用godot及工具过滤。用户级配置保存官方Godot AI认证条目和其他项目的连接；不要将原文件/备份上传仓库。`tools/setup_codex.py`只管理其声明支持的条目，保留已有自定义；`--check`是配置核对，不证明握手。

Godot AI的用户级域过滤可能同时影响其他项目。恢复`csg/gridmap/testing`等域时从官方dock调整并重新Configure，核对本项目客户端过滤和新会话；不为修Reol擅自改变其他项目配置。旧attach失效或返回`NEW_CLIENT_SESSION_REQUIRED`时按实际提示重连，不重复使用坏handle。

## skills怎样维护

项目自有入口为`godot-verify`、`godot-sim-architecture`、`open-world-2d`、`colony-sim-systems`和`spec-driven-game-dev`；其余是有来源记录的通用方法。技能按具体任务选用，项目导航由AGENTS和文档地图提供。

若新增方法确实跨任务复用，先改已有技能；只有触发与产物独立时才新建。第三方样例中的职业、属性面板、CI或验证配方不是Reol的全局规则。宿主/system/plugin缓存由官方入口维护，不手改。

## 更新或恢复时

先定位实际故障和所属组件，再核对上游稳定release、兼容与许可，保存可恢复配置。Godot AI使用官方插件整树与配置流程，技能更新保留来源与自有修改；不把引擎、MCP、模型和权限打包一起换。只有真实调用/输出能证明相应能力，文件存在或`enabled`不能证明握手。

旧更新清单、Node/CI迁移和竞品评估已进[tooling归档](../../archive/README.md)，不继续执行旧步骤。
