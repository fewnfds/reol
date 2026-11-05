# 当前代码架构与边界：依赖方向

## 依赖方向

```text
main / 场景装配
  输入与UI → runtime命令适配 → sim规则/过程/状态
                ↓                 ↓
          世界/人物呈现       data定义与开局
                ↘ persistence快照/迁移/文件边界
```

纯模拟不依赖HUD或祖先节点路径。运行适配负责绑定/命令与投影，不另存身体、库存或社会余额。当前业务autoload为`GameClock`，第三方另有MCP helper；未创建全量EventBus/ECS/EntityRegistry/SaveManager。

新环境场仍是隔离基础：`SimEnvironmentFieldCache`持可重建来源投影/脏块，`EnvironmentFieldComputeRuntime`选择CPU或RenderingDevice GPU。GPU线程只拿冻结快照，原子提交前核owner与revision；两后端没有第二时钟/原物/存档格式。当前未接入RegionalSimulation，普通热域仍按下表旧模型运行；接口/生命周期与验收见[F1证据](../../qa/20261105_field_compute_acceleration.md)。

`SimEnvironmentTemperatureState`是隔离候选中显式格的唯一实际温度owner；目标段/初值/时间锚点保存，边界计数索引恢复重建。`SimEnvironmentTemperatureSegments`只编译一个气候/天气/tide已知目标段，不持有温度或调度时钟。当前未替代Main，原物/来源/实际温度的联合变更和分块预算尚待接，规模限制见[F2a证据](../../qa/20261105_temperature_segments_and_budget.md)。
