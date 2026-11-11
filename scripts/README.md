# 代码入口与职责

先确定修改的事实归谁，再沿下面的路径读代码。当前停点见[HANDOFF](../docs/status/handoff.md)，领域owner见[索引](../docs/engineering/architecture/02-owners.md)。

| 从哪里开始 | 负责什么 |
|---|---|
| [main.gd](main.gd) → [WorldOpening](runtime/world_opening.gd) | 场景适配和新局装配；开局发行不会在读档时重跑 |
| [WorldContinuityRuntime](runtime/world_continuity_runtime.gd) | 已运行会话、玩家行旅、视图、计算后端的绑定与替换 |
| [RegionalSimulation](sim/regional_simulation.gd) → [execution](sim/execution/) | 共同边界、地区同步和领域执行顺序 |
| [VillageSimulation](sim/village_simulation.gd)、`sim/`、`sim/services/`、`sim/plants/` | 原状态、规则和领域过程；`sim`不依赖runtime或呈现节点 |
| [WorldSessionSnapshot](runtime/world_session_snapshot.gd) → [RegionalSnapshot](persistence/regional_snapshot.gd) → [world_save_domains](persistence/world_save_domains.gd) | 联合会话输入、独立候选和领域存读目录 |
| `persistence/`、`data/`、`core/` | 编码/文件、定义装配和共用坐标；`ThermalDefinitions`只验证热设备参数 |
| `world/`、`entities/`、`ui/` | 地图/人物呈现和可知界面，消费已提交状态 |
| `runtime/` | 输入、场景、呈现与计算后端适配；领域结果回到原owner采用 |
| `diagnostics/`、`tests/` | 临时人口/性能记录与三个短smoke；普通Main不加载诊断器 |

旧热量模拟器、独立环境验收会话、旧迁移链、boot与继任原型已删除；历史由Git/归档追溯。有效CPU批执行、环境GPU计算及CPU回退保留。

可选运行`python tools/check_structure.py --audit-code`查看字面引用、UID与层依赖疑点；动态调用仍需人工核对，工具不会自动删除代码，也不是提交门禁。文件放置见[project-structure](../docs/engineering/project-structure.md)，具体接口见[工程地图](../docs/engineering/README.md)。
