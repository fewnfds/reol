# 代码地图

正式入口`scenes/main.tscn`→`presentation/game.gd`；世界状态入口`sim/kernel/world.gd`。原状态、线程与数据流唯一说明在[运行架构](../docs/engineering/architecture.md)，扩展计算选择在[计算接入](../docs/engineering/execution-batches.md)。

旧领域框架已由本轮新内核替换；不要从历史类名或保留的旧JSON推断功能仍在运行。当前玩法与删减查[FEATURES](../docs/status/features.md)。
