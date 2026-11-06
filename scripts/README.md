# 代码目录职责

当前状态所有者、时间与提交边界只由[ARCHITECTURE](../docs/engineering/architecture.md)维护；格式/证据见[BASELINE](../docs/status/baseline.md)，当前授权见[HANDOFF](../docs/status/handoff.md)。本页不再逐包复制实现流水账。

| 路径 | 职责 |
|---|---|
| `sim/`、`sim/services/` | 纯规则、过程与可序列化状态 |
| `runtime/` | 输入/时钟/寻路/场景适配，提交命令与呈现投影 |
| `persistence/` | 数据编码、迁移、候选与文件；不决定社会后果 |
| `data/`、`core/` | 定义类/内容装配、少量通用坐标工具 |
| `world/`、`entities/`、`ui/` | 地图/区块/迷雾/相机，人物和有限可知界面 |
| `autoload/`、`social/` | 当前时钟；未接入游戏的继任原型 |

入口为[main.gd](main.gd)，持续世界在[regional_simulation.gd](sim/regional_simulation.gd)，地方生活在[village_simulation.gd](sim/village_simulation.gd)。新增文件按[PROJECT-STRUCTURE](../docs/engineering/project-structure.md)，改领域前查其计划和实际代码。

移动`.gd`连同`.gd.uid`并更新引用；先结构检查，再按变更做导入/行为验证。第三方addons不借重构修改。整理前逐包说明完整保存在[历史原文](../docs/archive/documentation_consolidation_20261104/scripts/README.md)。
