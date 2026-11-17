# 工具配置与维护

类型：工具记忆，故障/升级时查询。运行命令在[usage](usage.md)，agent载入机制在[DOCUMENTATION](../../DOCUMENTATION.md)；本页不规定每包检查工具或调整模型。

## 当前分工

| 组件 | 用途与边界 |
|---|---|
| Codex + 文件/CLI | 改代码、查Git、运行命令；现有路由/权限由宿主与本机配置管理 |
| Godot AI | 单个已核对项目的实时场景、运行、日志、输入与截图；用官方dock Configure生成认证attach，不猜端口或裸HTTP |
| Context7 | 查询目标版本文档；可用性依实际会话，没有该工具时使用官方文档 |
| Coding-Solo | 默认关闭的备用连接，不与主连接叠写同一编辑器 |
| 项目skills | 按领域提供容易遗漏的约束、review方法与可靠工具；与默认编码约定、现状架构和按需API资料分工 |
| 宗门离线报告 | `tools/settlement_report.py`消费现有周期日志，算相邻完成/拒绝/库存等变化；不增加运行期轮询、不替代真实性能采样或个人因果检查 |
| 原生review | 可按具体需要手动使用，已有项目模型配置不意味着每包自动执行 |

Godot、插件、技能/工具各有采用版本；实际引擎只登记在[BASELINE](../../status/baseline.md)，第三方pin/许可按[NOTICES](../../../THIRD_PARTY_NOTICES.md)维护。不因文档旧版本示例自动升级或安装依赖。

## 配置在哪里

项目`.codex/config.toml`是忽略的本机覆盖，可配置Context7、备用godot及工具过滤。用户级配置保存官方Godot AI认证条目和其他项目的连接；不要将原文件/备份上传仓库。`tools/setup_codex.py`只管理其声明支持的条目，保留已有自定义；`--check`是配置核对，不证明握手。

项目不再维护OpenCode专属配置或技能目录。共享`.agents/skills/`仍服务当前开发；Coding-Solo包装器仍由Codex备用配置引用。Godot AI第三方整包自带多客户端适配，其中的OpenCode模块由插件注册器引用，不按项目遗留配置拆删；个人全局客户端配置不属项目清理范围。

Godot AI的用户级域过滤可能同时影响其他项目。恢复`csg/gridmap/testing`等域时从官方dock调整并重新Configure，核对本项目客户端过滤和新会话；不为修Reol擅自改变其他项目配置。旧attach失效或返回`NEW_CLIENT_SESSION_REQUIRED`时按实际提示重连，不重复使用坏handle。

## skills怎样维护

项目在`.agents/skills/`维护按任务选择的领域入口，不设数量上限或每轮必读清单。名称/描述供宿主选择，正文保留影响决策的检查，相关reference只在对应问题出现时读。

| 入口 | 使用范围 / 保留的专门知识 |
|---|---|
| [godot-sim-architecture](../../../.agents/skills/godot-sim-architecture/SKILL.md) | 模拟功能的owner、访问形状、跨步采用与恢复；接入原框架，避免套每NPC一个Node的教程 |
| [simulation-game-design](../../../.agents/skills/simulation-game-design/SKILL.md) | 跨系统经济/生态/社会玩法的处境取舍、反馈、低美术表达与实验；普通bug/微调/纯优化不触发 |
| [godot-verify](../../../.agents/skills/godot-verify/SKILL.md) | 相关短验证及headless导入、异步、错误退出/挂起排错 |
| [create-game-assets](../../../.agents/skills/create-game-assets/SKILL.md) | 纯二维斜俯视、脚点/图集接入；Pillow透明/尺寸/色数报告与联系表脚本 |
| [godot-gdscript](../../../.agents/skills/godot-gdscript/SKILL.md) | 类型/失败边界、Node与信号/await生命周期；按需资源引用检查器 |
| [godot-resources](../../../.agents/skills/godot-resources/SKILL.md) | 定义编译/校验、共享Resource与深层隔离、加载边界 |
| [godot-ui-input](../../../.agents/skills/godot-ui-input/SKILL.md) | Control布局、焦点/输入消费、按住/边沿与直接控制交接 |
| [godot-motion-navigation](../../../.agents/skills/godot-motion-navigation/SKILL.md) | 身体/脚点/坐标、连续碰撞、导航新鲜度与真实到达 |
| [godot-decision-systems](../../../.agents/skills/godot-decision-systems/SKILL.md) | 个人认识、效用/策略、Running/抢占及失败重试 |
| [colony-sim-systems](../../../.agents/skills/colony-sim-systems/SKILL.md) | 工作/工位、物资权属、原子转移和取消/恢复 |
| [godot-character-rules](../../../.agents/skills/godot-character-rules/SKILL.md) | 基础/派生数值、可逆来源、状态/装备/成长边界 |
| [save-systems](../../../.agents/skills/save-systems/SKILL.md) | 持久字段、独立候选恢复、格式边界、磁盘失败保护 |
| [godot-world-generation](../../../.agents/skills/godot-world-generation/SKILL.md) | seed/顺序、生成与持久变化、区块接续；按需TileMap检查 |
| [godot-2d-presentation](../../../.agents/skills/godot-2d-presentation/SKILL.md) | Camera2D、排序、动画/反馈、共同显示时间；按需shader/GPU检查 |
| [godot-audio](../../../.agents/skills/godot-audio/SKILL.md) | 现有战斗音频、voice限制、混音/音量与真实试听 |
| [godot-export](../../../.agents/skills/godot-export/SKILL.md) | Windows预设、非资源过滤、当前/历史包与独立冷启动 |
| [performance-optimization](../../../.agents/skills/performance-optimization/SKILL.md) | CPU/GPU/等待分诊、端到端成本、有效产出与同条件测量 |
| [level-design](../../../.agents/skills/level-design/SKILL.md) | 手工空间/开局的尺度、服务可用、可读性与真实试玩 |
| [dialogue-systems](../../../.agents/skills/dialogue-systems/SKILL.md) | 触及分支叙事时的会话/选择图/一次效果；不是当前已有剧情引擎 |

36→3的上一轮删减漏核了领域约束，不能认定剩余三个入口已经等效覆盖。前次恢复/合并改写为18个窄入口：保留需要长期执行的检查，去掉不适用的跨引擎实现、品类剧本和重复入门样例。33项原技能逐一的价值、原覆盖缺口、最终去向与替代资料见[覆盖审查](skill-coverage.md)。原headless指导继续并入验证reference；范围收敛的防文书膨胀条款并入开发循环。

本次范式对齐保留上述18项，新增缺失的`simulation-game-design`，合计19项；决策/工作/资源/验证/性能只补本领域的相关方法，不要求一起加载。新技能按pbzona的两项MIT设计指导收窄改写，来源/pin/许可见[NOTICES](../../../THIRD_PARTY_NOTICES.md)，为何不整套安装以及一手资料采用边界见[研究取舍](../../../design/research/development-paradigms.md)。详细模型与实验说明集中在[模拟方法](../simulation-methods.md)，不在每个技能复制全文。

原`check_godot_project.py`恢复到`godot-gdscript/scripts/`，保持原代码与许可，按场景/资源变更调用。它与`tools/check_structure.py`互补，不能用“没有运行时代码调用方”否定开发工具；也不把两者做成每轮重复门禁。已用好/坏小项目核UID、大小写、内部引用与场景连接，仍不宣称静态工具等同Godot解析器。

清理依据是内容适配、重复与可执行价值；没有使用遥测，不能据此认定某技能从未用过或导致某缺陷。数量和格式通过都不证明模型实际遵守。质量同时依赖[默认约定](../../../AGENTS.md#实现与review先检查访问规模)、[开发循环](../workflow/testing.md)与任务实际证据。

新增或删并技能先确认跨任务职责、非显然风险、当前覆盖与独有工具；合并需保住实质检查和触发，不能只剩导航链接，也不能因为模型“理论上懂”就删掉重要review约束。API手册、目录导航或单次进度不独立建技能；但通用领域知识经过项目适配、能改变设计/验证选择时可以保留。具体API查目标版本官方资料，不整套换装未经核对的外部skill。宿主/system/plugin及用户个人技能由各自入口维护，本次只修改项目目录。

## 更新或恢复时

先定位实际故障和所属组件，再核对上游稳定release、兼容与许可，保存可恢复配置。Godot AI使用官方插件整树与配置流程，技能更新保留来源与自有修改；不把引擎、MCP、模型和权限打包一起换。只有真实调用/输出能证明相应能力，文件存在或`enabled`不能证明握手。

旧更新清单、Node/CI迁移和竞品评估已进[tooling归档](../../archive/README.md)，不继续执行旧步骤。
