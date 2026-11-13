# 项目记忆地图

按问题定位正文，表格没有阅读顺序。载入机制与维护方法见[文档职责](DOCUMENTATION.md)。

| 要回答的问题 / 检索词 | 正文归属 | 性质 |
|---|---|---|
| 正在做什么、允许做到哪、停点、未提交、受保护工作 | [HANDOFF](status/handoff.md) | 当前接续，直接替换过时内容 |
| 技术栈、目标硬件、共同因果、数据安全等不可擅改边界 | [constraints](engineering/constraints.md) | 稳定约束 |
| 世界、空间、环境、生命、认识的已定规则 | [design/rules](../design/rules/README.md) | 用户已定；各页“未定”仍是开放问题 |
| 当前做什么框架、先后取舍、性能目标 | [唯一主计划](plans/foundation-priorities.md) | 当前计划；不自动授权执行 |
| 引擎/存档版本、有效测量、性能是否达标 | [BASELINE](status/baseline.md)、[数值样本](status/performance.json) | 当前解释 / 可执行的历史数值 |
| 能玩什么、键位、未实现玩法 | [FEATURES](status/features.md) | 当前能力；不重复测量和计划 |
| 七个领域谁负责、跨域影响、原owner在哪 | [领域职责](engineering/architecture/05-framework-domains.md)、[当前实现](engineering/architecture.md) | 逻辑边界 / 当前代码索引 |
| 新计算接入、时间/事件、空间/行动、环境/植物、存读接口 | [工程接口地图](engineering/README.md) | 实现参考；可重构 |
| 当前美术素材、动作、来源、图鉴与离线重建 | [assets](../assets/README.md) | 当前素材唯一清单 |
| 数据定义、开局、内容装配 | [data](../data/README.md) | 数据入口与实际清单 |
| 游戏愿景、候选机制与研究来源 | [design](../design/README.md)、[产品层次](plans/roadmap.md) | 愿景 / 候选 / 研究 |
| 当前怎样开发和验证、运行/测量命令 | [开发循环](engineering/workflow/testing.md)、[命令](engineering/tooling/usage.md) | 当前方法 / 工具语法 |
| MCP配置、插件/技能来源、升级与恢复 | [tooling/setup](engineering/tooling/setup.md) | 按工具故障或更新需求读取 |
| 过去为何这样做、旧报告/截图/提示词 | [archive](archive/README.md) | 历史，不产生当前要求 |

## 查找已有内容

可按概念或代码标识搜索，例如`rg -n "存档|restore" docs/engineering scripts/sim/kernel`。archive是历史，追溯时显式`rg --no-ignore "关键词" docs/archive`。
