# A2a真实地面来源分块缓存验证

2026-11-05。本页仍在填验收证据，未完成时不能据标题宣称包通过。范围为[缓存合同](../engineering/environment-ground-cache-contract.md)；普通Main、实际温度/五行响应、移动携源和GPU不属于本包。

## 起点与保护

起点`a39b8f6`，四份原环境WIP哈希按`logs/world_lifecycle/protected.json`核对，保留且不混入精确SHA验收。doctor为Godot4.7.2 stable；审查配置为Sol/custom。

## 进行中证据

- 算术/epoch初次定向：1404断言、0失败，日志`logs/environment_a2/targeted-initial.log`。
- 64²最大半径、128²混合半径、256²最大半径真实物品基准已通过各自来源/缓存对照；完整JSON在`logs/benchmarks/environment_ground_cache_*`。
- 初测1024次热读p95约9ms，未达初始5ms目标；后续数值与最终版本须继续记录，不修改门槛或把单次读取冒充1024次。
- 512²、综合缓存定向、精确SHA完整回归与一次原生代码审查待补。
