# 代码地图

正式入口`scenes/main.tscn`→`presentation/game.gd`；世界状态入口`sim/kernel/world.gd`。原状态、线程与数据流唯一说明在[运行架构](../docs/engineering/architecture.md)，扩展计算选择在[计算接入](../docs/engineering/execution-batches.md)。

旧领域框架已由本轮新内核替换；不要从历史类名或保留的旧JSON推断功能仍在运行。当前玩法与删减查[FEATURES](../docs/status/features.md)。

战斗作者数据类型在`sim/definitions/combat/`；动作/弹体、持续状态、区域与器物过程在`sim/kernel/`分别持有，主线程只读展示。内容目录、编辑步骤及新增机制的接缝见[战斗制作合同](../design/systems/combat_framework/act_and_barrage.md#101-定义施放和表现的接入合同)，不为每个技能增设独立脚本后端。
