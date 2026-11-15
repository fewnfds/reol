# 代码地图

正式入口`scenes/main.tscn`→`presentation/game.gd`；世界组合根为`sim/kernel/world.gd`。状态owner、线程和数据流见[运行架构](../docs/engineering/architecture.md)，计算接入见[批执行](../docs/engineering/execution-batches.md)。

- `sim/definitions/actions/`：公共作用、成本、池、状态和反应Resource。
- `sim/definitions/combat/`：ACT动作、交付、配置、实体与库Resource。
- `sim/kernel/`：唯一模拟后端；各领域持有自己的原状态，公共准入与结果反应复用这些领域。
- `sim/execution/`：Godot线程池的有限独占批与join。
- `sim/diagnostics/`：显式开启的有界负载探针，不参与普通开局。
- `presentation/`：输入、UI、只读快照表现、批量渲染与音画反馈。

常规内容通过Resource扩展，特殊算法依附实际机制宿主；制作与扩展合同见[公共行动框架](../design/systems/action_effect_framework.md)和[战斗制作](../design/systems/combat_framework/act_and_barrage.md#101-定义施放和表现的接入合同)。当前操作与边界见[FEATURES](../docs/status/features.md)。
